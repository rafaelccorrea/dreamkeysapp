import 'dart:io' show File;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/autentique_status_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/services/sale_forms_service.dart'
    show saleFormLinkAbrivel, saleFormSignerExcluido;
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../utils/proposal_signature_rules.dart';
import 'proposal_row_actions.dart' show showProposalPdfSheet;

/// Bottom sheet de assinaturas da PROPOSTA — paridade com
/// `ProposalSignaturesModalPrivate.tsx` (web).
///
/// Três etapas (1 comprador, 2 proprietário, 3 corretor/captadores); a 2 e a
/// 3 só abrem quando o back libera (`historico.maxEtapaLiberadaParaEnvio`).
/// Cada etapa mostra só as próprias assinaturas; o formulário some quando a
/// etapa já tem assinatura concluída. Modo de envio vale para todos:
/// **Enviar por e-mail** (nome + e-mail) ou **Gerar apenas link** (só nome —
/// o link sai por cópia/WhatsApp).
///
/// Linhas do usuário logado ("você") ganham **Assinar**, que abre o link do
/// Autentique fora do app.
///
/// [defaultSigners] ficou como reserva: o sheet preenche sozinho pela etapa
/// (proponente / proprietário / 1º corretor ou captador), como o web; a lista
/// passada só é usada se a proposta não carregar.
Future<void> showProposalSignaturesSheet(
  BuildContext context, {
  required String proposalId,
  required String proposalNumber,
  int etapa = 1,
  bool initialHistorico = false,
  List<ProposalSignerInput> defaultSigners = const [],
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _ProposalSignaturesSheet(
      proposalId: proposalId,
      proposalNumber: proposalNumber,
      etapa: etapa,
      initialHistorico: initialHistorico,
      defaultSigners: defaultSigners,
      onChanged: onChanged,
    ),
  );
}

class _ProposalSignaturesSheet extends StatefulWidget {
  const _ProposalSignaturesSheet({
    required this.proposalId,
    required this.proposalNumber,
    required this.etapa,
    required this.initialHistorico,
    required this.defaultSigners,
    this.onChanged,
  });

  final String proposalId;
  final String proposalNumber;
  final int etapa;
  final bool initialHistorico;
  final List<ProposalSignerInput> defaultSigners;
  final VoidCallback? onChanged;

  @override
  State<_ProposalSignaturesSheet> createState() =>
      _ProposalSignaturesSheetState();
}

const Map<String, String> _kEventLabels = {
  'etapa_1_criada': 'Etapa 1 criada',
  'proposta_enviada': 'Proposta enviada para assinatura',
  'assinatura_comprador': 'Assinatura do comprador',
  'assinatura_proprietario': 'Assinatura do proprietário',
  'etapa_3_vinculada': 'Etapa 3 vinculada',
};

class _ProposalSignaturesSheetState extends State<_ProposalSignaturesSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  ProposalHistorico? _historico;
  PurchaseProposal? _proposta;
  List<ProposalSignature> _signatures = const [];

  /// id da assinatura → link já gerado (`signatureUrl`, fora do model).
  Map<String, String> _urls = const {};
  String? _error;
  int _errorStatus = 0;
  bool _sending = false;
  bool _syncing = false;
  bool _uploading = false;
  bool _pdfLoading = false;
  String? _linkBusyId;

  /// Integração Autentique inativa → envio travado (web: `AutentiqueSendGate`).
  bool _autentiqueBlocked = false;

  /// Reenvio pelo WhatsApp da empresa: só aparece com `canResend`.
  ProposalWhatsappEnvio? _waEnvio;

  final ImagePicker _imagePicker = ImagePicker();

  late int _etapa;
  final TextEditingController _docName = TextEditingController();
  final TextEditingController _docMessage = TextEditingController();
  bool _docNameTouched = false;
  bool _porEmail = true;
  final List<_SignerForm> _forms = [];

  /// Etapa cujo formulário já foi pré-preenchido (evita apagar digitação).
  int? _prefilledEtapa;

  @override
  void initState() {
    super.initState();
    _etapa = math.max(1, math.min(3, widget.etapa));
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialHistorico ? 1 : 0,
    );
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _docName.dispose();
    _docMessage.dispose();
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  Color get _green =>
      _isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  Color get _red =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
  /// Âmbar para TEXTO: o de status (#E6B84C) não passa contraste no branco.
  Color get _warnText => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;
  Color get _blue =>
      _isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

  // ─── Carga ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = PurchaseProposalsService.instance;
    final histFut = svc.getHistorico(widget.proposalId);
    final sigsFut = _listarAssinaturas();
    final propFut =
        _proposta == null ? svc.getById(widget.proposalId) : null;
    // Web: `useAutentiqueStatus` (trava o envio) e, no app, a
    // disponibilidade do reenvio pelo WhatsApp da empresa.
    final autFut = AutentiqueStatusService.instance.isBlocked();
    final waFut = svc.getWhatsappEnvio(widget.proposalId);
    final histRes = await histFut;
    final sigs = await sigsFut;
    final propRes = await propFut;
    final autBlocked = await autFut;
    final wa = await waFut;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _autentiqueBlocked = autBlocked;
      _waEnvio = wa;
      if (histRes.success && histRes.data != null) {
        _historico = histRes.data;
      } else {
        _error = histRes.message ?? 'Não foi possível carregar as assinaturas.';
        _errorStatus = histRes.statusCode;
      }
      if (sigs != null) {
        _signatures = sigs.$1;
        _urls = sigs.$2;
      }
      if (propRes != null && propRes.success && propRes.data != null) {
        _proposta = propRes.data;
      }
      if (_etapa > _maxLiberada) _etapa = _maxLiberada;
    });
    _prefillEtapa();
  }

  /// `GET …/assinaturas` lido cru para ter o `signatureUrl` (o model da
  /// proposta não o carrega) — assim o link existente não gera `POST /link`.
  Future<(List<ProposalSignature>, Map<String, String>)?>
      _listarAssinaturas() async {
    try {
      final res = await ApiService.instance.get<dynamic>(
        ApiConstants.purchaseProposalAssinaturas(widget.proposalId),
      );
      if (!res.success) return null;
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      if (list is! List) return (const <ProposalSignature>[], const <String, String>{});
      final sigs = <ProposalSignature>[];
      final urls = <String, String>{};
      for (final m in list.whereType<Map>()) {
        final j = Map<String, dynamic>.from(m);
        final s = ProposalSignature.fromJson(j);
        sigs.add(s);
        final u = (j['signatureUrl'] ?? j['signature_url'])?.toString().trim();
        if (u != null && u.isNotEmpty) urls[s.id] = u;
      }
      return (sigs, urls);
    } catch (_) {
      return null;
    }
  }

  // ─── Regras (espelho do web) ─────────────────────────────────────────────

  int get _maxLiberada =>
      math.max(1, math.min(3, _historico?.maxEtapaLiberadaParaEnvio ?? 1));

  List<ProposalSignature> get _daEtapa =>
      _signatures.where((s) => s.etapa == _etapa).toList();

  bool get _alreadySent => _signatures.isNotEmpty;

  bool get _mostrarFormulario {
    final daEtapa = _daEtapa;
    final nenhumaAssinada = daEtapa.every((s) => !_assinada(s));
    return !_alreadySent || nenhumaAssinada;
  }

  static bool _assinada(ProposalSignature s) =>
      s.status.toLowerCase() == 'signed';

  static bool _encerrada(ProposalSignature s) {
    final st = s.status.toLowerCase();
    return st == 'signed' ||
        st == 'rejected' ||
        st == 'cancelled' ||
        st == 'canceled';
  }

  String get _meuEmail =>
      (ModuleAccessService.instance.userPermissions?.userEmail ?? '')
          .trim()
          .toLowerCase();

  bool _ehVoce(String? email) {
    final me = _meuEmail;
    return me.isNotEmpty && (email ?? '').trim().toLowerCase() == me;
  }

  bool get _isGestor {
    final role = ModuleAccessService.instance.userRole?.toLowerCase();
    return role == 'manager' || role == 'admin' || role == 'master';
  }

  /// Etapas em que ainda cabe anexar a ficha física: liberadas, sem anexo
  /// aprovado e não concluídas por assinatura (todas assinadas).
  List<int> get _etapasDisponiveis {
    final h = _historico;
    final aprovadas = <int>{
      for (final a in h?.attachments ?? const <ProposalAttachment>[])
        if (a.status.toLowerCase() == 'approved') a.etapa,
    };
    final out = <int>[];
    for (var i = 1; i <= _maxLiberada; i++) {
      final sigs = (h?.signatures ?? const <ProposalSignature>[])
          .where((s) => s.etapa == i)
          .toList();
      final completa = sigs.isNotEmpty && sigs.every(_assinada);
      if (!aprovadas.contains(i) && !completa) out.add(i);
    }
    return out;
  }

  /// Aprovar/rejeitar anexo: no web só existe no modal de Anexos, que só
  /// abre com alguma etapa disponível para anexo
  /// (`ProposalSignaturesModalPrivate.tsx`, `mostrarBotaoAnexarFisica`;
  /// `PropostaAnexosModalPrivate.tsx`, `pending_approval && isGestor`).
  bool _podeDecidirAnexo(ProposalAttachment a) => proposalPodeDecidirAnexo(
        isGestor: _isGestor,
        status: a.status,
        etapasDisponiveis: _etapasDisponiveis,
      );

  String _etapaLabel(int etapa) => switch (etapa) {
        1 => 'Comprador',
        2 => 'Proprietário',
        _ => 'Corretor/Captadores',
      };

  /// Pré-preenche o formulário da etapa quando ela ainda não tem assinaturas
  /// (1 proponente, 2 proprietário, 3 primeiro corretor ou captador).
  void _prefillEtapa() {
    if (!mounted || _prefilledEtapa == _etapa) return;
    if (_alreadySent && _daEtapa.isNotEmpty) {
      _prefilledEtapa = _etapa;
      if (_forms.isEmpty) setState(() => _forms.add(_SignerForm()));
      return;
    }
    String nome = '';
    String email = '';
    final p = _proposta;
    if (p != null) {
      if (_etapa == 1) {
        nome = p.proponentName ?? '';
        email = p.proponentEmail ?? '';
      } else if (_etapa == 2) {
        nome = p.ownerName ?? '';
        email = p.ownerEmail ?? '';
      } else {
        Map? primeiro;
        for (final k in ['brokersData', 'captadoresData']) {
          final l = p.raw[k];
          if (l is List && l.whereType<Map>().isNotEmpty) {
            primeiro = l.whereType<Map>().first;
            break;
          }
        }
        nome = (primeiro?['nome'] ?? primeiro?['name'] ?? '').toString();
        email = (primeiro?['email'] ?? '').toString();
      }
    } else if (_etapa == widget.etapa && widget.defaultSigners.isNotEmpty) {
      nome = widget.defaultSigners.first.name;
      email = widget.defaultSigners.first.email;
    }
    final n = _proposalNumber;
    setState(() {
      _prefilledEtapa = _etapa;
      for (final f in _forms) {
        f.dispose();
      }
      _forms
        ..clear()
        ..add(_SignerForm(name: nome.trim(), email: email.trim()));
      _porEmail = email.trim().isNotEmpty;
      _docName.text =
          'Proposta de Compra $n${_etapa == 3 ? ' – Etapa 3' : ''}';
      if (_docMessage.text.trim().isEmpty) {
        _docMessage.text = 'Por favor, assine a proposta de compra conforme '
            'os dados informados.';
      }
    });
  }

  String get _proposalNumber {
    final n = widget.proposalNumber.trim();
    if (n.isNotEmpty) return n;
    return _proposta?.proposalNumber ?? '';
  }

  void _trocarEtapa(int e) {
    if (e > _maxLiberada || e == _etapa) return;
    setState(() => _etapa = e);
    _prefillEtapa();
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  /// Mensageiro PRÓPRIO do sheet: o da página fica atrás do sheet (88% da
  /// altura) e todo retorno — "Link copiado", erro de envio — sumia.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void _snack(String msg) {
    if (!mounted) return;
    final messenger =
        _messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final res = await PurchaseProposalsService.instance
        .syncAssinaturas(widget.proposalId);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (res.success) {
      _snack('Assinaturas verificadas.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao verificar.');
    }
  }

  Future<void> _enviar() async {
    if (_autentiqueBlocked) {
      _snack(kAutentiqueInactiveMessage);
      return;
    }
    final nome = _docName.text.trim();
    setState(() => _docNameTouched = true);
    if (nome.isEmpty) {
      _snack('Nome do documento é obrigatório.');
      return;
    }
    final signers = <Map<String, dynamic>>[];
    for (final f in _forms) {
      final n = f.name.text.trim();
      final e = f.email.text.trim();
      if (saleFormSignerExcluido(email: e, name: n)) {
        _snack('Caixa administrativa genérica ou nome institucional da '
            'imobiliária não podem ser enviados. Use pessoas físicas.');
        return;
      }
      if (_porEmail) {
        if (e.isEmpty) {
          _snack('Informe o e-mail do signatário quando "Enviar por e-mail" '
              'estiver marcado.');
          return;
        }
        signers.add({'email': e, if (n.isNotEmpty) 'name': n, 'action': 'SIGN'});
      } else {
        if (n.isEmpty) {
          _snack('Informe o nome do signatário quando "Gerar apenas link" '
              'estiver marcado.');
          return;
        }
        signers.add({'name': n, 'action': 'SIGN'});
      }
    }
    if (signers.isEmpty) {
      _snack('Adicione ao menos um signatário.');
      return;
    }
    final msg = _docMessage.text.trim();
    setState(() => _sending = true);
    ApiResponse<dynamic> res;
    try {
      res = await ApiService.instance.post<dynamic>(
        ApiConstants.purchaseProposalAssinaturas(widget.proposalId),
        body: {
          'document': {
            'name': nome,
            if (msg.isNotEmpty) 'message': msg,
            'refusable': false,
            'sortable': false,
          },
          'signers': signers,
          'etapa': _etapa,
        },
      );
    } catch (e) {
      res = ApiResponse.error(message: e.toString(), statusCode: 0);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      if (_porEmail) {
        // Web (`onSent`): envio por e-mail fecha a folha e recarrega a lista
        // — o retorno aparece no mensageiro da página, que fica à vista.
        final pageMessenger = ScaffoldMessenger.maybeOf(context);
        widget.onChanged?.call();
        Navigator.of(context).pop();
        pageMessenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Proposta enviada para assinatura.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      // Só link (web `onEtapaLiberada`): a folha fica aberta para copiar ou
      // mandar cada link, e a lista recarrega por trás.
      _snack('Envio criado. Use Copiar link ou WhatsApp para cada signatário '
          'na lista.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao enviar para assinatura.');
    }
  }

  /// PDF da etapa pela folha de arquivo do app (Compartilhar / Salvar no
  /// aparelho) — `Uri.file` não abre no Android nem no iOS.
  Future<void> _abrirPdf({bool comAssinado = false}) async {
    setState(() => _pdfLoading = true);
    await showProposalPdfSheet(
      context,
      proposalId: widget.proposalId,
      numero: _proposalNumber,
      etapa: _etapa,
      incluirAutentique: comAssinado,
    );
    if (mounted) setState(() => _pdfLoading = false);
  }

  /// Etapa atual com documento assinado no Autentique: aí o "PDF + assinado"
  /// (ZIP do back, `incluirAutentique`) faz sentido.
  bool get _etapaTemAssinado => proposalTemAssinado(
        (_historico?.signatures ?? _signatures)
            .where((s) => s.etapa == _etapa)
            .map((s) => s.status),
      );

  /// Usa o link já existente; só pede `POST /link` quando não há.
  Future<String?> _resolveLink(ProposalSignature sig) async {
    final pronto = _urls[sig.id];
    if (pronto != null && pronto.isNotEmpty) return pronto;
    setState(() => _linkBusyId = sig.id);
    final res = await PurchaseProposalsService.instance
        .obterLinkAssinatura(widget.proposalId, sig.id);
    if (!mounted) return null;
    setState(() => _linkBusyId = null);
    if (res.success && res.data != null) {
      _urls = {..._urls, sig.id: res.data!};
      return res.data;
    }
    _snack(res.message ?? 'Erro ao obter link.');
    return null;
  }

  Future<void> _copiarLink(ProposalSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Link copiado. Envie apenas ao signatário correspondente.');
  }

  Future<void> _whatsapp(ProposalSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    final msg = 'Olá! Segue o link para assinar a proposta '
        '$_proposalNumber:\n\n$link';
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _assinar(ProposalSignature sig) async {
    final link = saleFormLinkAbrivel(await _resolveLink(sig));
    if (!mounted) return;
    if (link == null) {
      _snack('Link de assinatura indisponível.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      _snack('Não foi possível abrir o link de assinatura.');
      return;
    }
    _snack('Depois de assinar, toque em Verificar para atualizar o status.');
  }

  Future<void> _reenviarEmail(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance
        .reenviarPorEmail(widget.proposalId, sig.id);
    if (!mounted) return;
    _snack(res.success
        ? 'E-mail reenviado.'
        : res.message ?? 'Erro ao reenviar e-mail.');
  }

  /// Reenvio pelo WhatsApp da empresa — só oferecido com `canResend`
  /// (`GET …/whatsapp-envio`); o retorno diz quantas saíram de fato
  /// (`{sent, skippedNoPhone, failed}`), nunca "iniciado" no escuro.
  Future<void> _reenviarWhatsapp(ProposalSignature sig) async {
    setState(() => _linkBusyId = sig.id);
    final res = await PurchaseProposalsService.instance
        .reenviarUmWhatsapp(widget.proposalId, sig.id);
    if (!mounted) return;
    setState(() => _linkBusyId = null);
    _snack(res.success
        ? proposalWhatsappResumo(res.data)
        : res.message ?? 'Erro ao reenviar pelo WhatsApp.');
  }

  Future<void> _anexarFicha() async {
    final etapas = _etapasDisponiveis;
    if (etapas.isEmpty) {
      _snack('Nenhuma etapa disponível para anexo no momento.');
      return;
    }
    final etapa =
        etapas.length == 1 ? etapas.first : await _escolherEtapa(etapas);
    if (etapa == null || !mounted) return;
    final origem = await _escolherOrigem();
    if (origem == null || !mounted) return;

    File? file;
    try {
      if (origem == 'camera') {
        final XFile? shot = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (shot != null) file = File(shot.path);
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: _kAnexoExtensoes,
          allowMultiple: false,
        );
        final path = result?.files.single.path;
        if (path != null) file = File(path);
      }
    } catch (_) {
      _snack(origem == 'camera'
          ? 'Não foi possível abrir a câmera.'
          : 'Não foi possível abrir o seletor de arquivos.');
      return;
    }
    if (file == null || !mounted) return;

    final ext = file.path.split('.').last.toLowerCase();
    if (!_kAnexoExtensoes.contains(ext)) {
      _snack('Formato inválido. Use PDF, JPG, PNG ou WEBP.');
      return;
    }
    if (await file.length() > 15 * 1024 * 1024) {
      _snack('Arquivo acima do limite de 15MB.');
      return;
    }

    setState(() => _uploading = true);
    final res = await PurchaseProposalsService.instance.uploadAnexo(
      widget.proposalId,
      file,
      etapa: etapa,
      uploadedByName: ModuleAccessService.instance.userPermissions?.userName,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.success && res.data != null) {
      final approved = res.data!.status.toLowerCase() == 'approved';
      // Web: anuncia a PRÓXIMA etapa liberada (`PropostaAnexosModalPrivate`).
      _snack(approved
          ? proposalAnexoAprovadoMsg(etapa, noUpload: true)
          : 'Anexo enviado. Aguardando aprovação do gestor.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao anexar ficha.');
    }
  }

  Future<int?> _escolherEtapa(List<int> etapas) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text(
                  'Anexar em qual etapa?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              for (final e in etapas)
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: _accent.withValues(alpha: 0.14),
                    child: Text(
                      '$e',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    'Etapa $e — ${_etapaLabel(e)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(ctx).pop(e),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _escolherOrigem() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Text(
                  'Anexar ficha física',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  'Foto ou arquivo da ficha assinada no papel.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(ctx),
                      ),
                ),
              ),
              ListTile(
                leading: Icon(LucideIcons.camera, color: _accent),
                title: const Text('Foto da câmera'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
              ListTile(
                leading: Icon(LucideIcons.fileUp, color: _accent),
                title: const Text('Arquivo (PDF ou imagem)'),
                onTap: () => Navigator.of(ctx).pop('file'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aprovarAnexo(ProposalAttachment att) async {
    final res = await PurchaseProposalsService.instance
        .aprovarAnexo(widget.proposalId, att.id);
    if (!mounted) return;
    if (res.success) {
      _snack(proposalAnexoAprovadoMsg(att.etapa));
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao aprovar anexo.');
    }
  }

  Future<void> _rejeitarAnexo(ProposalAttachment att) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar anexo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: _filledDecoration(
            ctx,
            label: 'Motivo da rejeição *',
            hint: 'Explique por que a ficha não foi aceita',
            alignLabel: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final txt = controller.text.trim();
              if (txt.isEmpty) return;
              Navigator.of(ctx).pop(txt);
            },
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    final res = await PurchaseProposalsService.instance
        .rejeitarAnexo(widget.proposalId, att.id, reason: reason);
    if (!mounted) return;
    if (res.success) {
      _snack('Anexo rejeitado.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao rejeitar anexo.');
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canUpdate =
        ModuleAccessService.instance.hasPermission('proposal:update');
    final mq = MediaQuery.of(context);
    final altura = math.max(
      0.0,
      math.min(
        mq.size.height * 0.88,
        mq.size.height - mq.viewInsets.bottom - mq.padding.top - 12,
      ),
    );
    // Teclado aberto (tela baixa): o cabeçalho encolhe para uma linha e o
    // formulário fica com a altura que sobra.
    final compacto = mq.viewInsets.bottom > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: altura,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ThemeHelpers.backgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
          ),
        ),
        child: ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: _sheetBody(canUpdate: canUpdate, compacto: compacto),
          ),
        ),
      ),
    );
  }

  Widget _sheetBody({required bool canUpdate, required bool compacto}) {
    return Column(
      children: [
        _SheetHeader(
          proposalNumber: _proposalNumber,
          titulo: 'ASSINATURAS · ETAPA $_etapa · '
              '${_etapaLabel(_etapa).toUpperCase()}',
          compacto: compacto,
          onClose: () => Navigator.of(context).pop(),
        ),
        TabBar(
          controller: _tab,
          indicatorColor: _accent,
          indicatorWeight: 2.5,
          labelColor: _accent,
          unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
          dividerColor: ThemeHelpers.borderLightColor(context),
          labelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(height: 42, text: 'Assinaturas'),
            Tab(height: 42, text: 'Histórico'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildSendTab(canUpdate: canUpdate),
              _buildHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }

  /// Esqueleto fiel à aba: seletor de etapa, ações, rótulo e linhas de
  /// signatário (avatar, nome, e-mail e pílula de status).
  Widget _skeleton() {
    Widget signer() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 36, height: 36, borderRadius: 18),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 150, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 190, height: 11),
                    SizedBox(height: 8),
                    SkeletonBox(width: 86, height: 20, borderRadius: 999),
                  ],
                ),
              ),
            ],
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 44, borderRadius: 8)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 44, borderRadius: 8)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 44, borderRadius: 8)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: const [
            SkeletonBox(width: 132, height: 36, borderRadius: 10),
            SizedBox(width: 8),
            SkeletonBox(width: 96, height: 36, borderRadius: 10),
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonText(width: 170, height: 11),
        signer(),
        signer(),
        signer(),
      ],
    );
  }

  Widget _buildSendTab({required bool canUpdate}) {
    if (_loading && _historico == null) return _skeleton();
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (_error != null && _historico == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        children: [
          AppErrorState.fromApi(
            message: _error,
            statusCode: _errorStatus,
            onRetry: _load,
            dense: true,
          ),
        ],
      );
    }
    final daEtapa = _daEtapa;
    final assinadas = daEtapa.where(_assinada).length;
    final mostrarForm = canUpdate && _mostrarFormulario;
    final nomeVazio = _docNameTouched && _docName.text.trim().isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _EtapaPicker(
          current: _etapa,
          maxLiberada: _maxLiberada,
          accent: _accent,
          onChanged: _trocarEtapa,
          onLocked: (e) => _snack(
            'A Etapa $e abre quando a Etapa ${e - 1} for concluída.',
          ),
        ),
        // Motivo do cadeado à vista (não só no toque).
        if (_maxLiberada < 3)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _InfoLine(
              icon: LucideIcons.lock,
              color: muted,
              text: 'A Etapa ${_maxLiberada + 1} abre quando a Etapa '
                  '$_maxLiberada for concluída.',
            ),
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AcaoTexto(
              icon: LucideIcons.fileText,
              label: _pdfLoading ? 'Carregando PDF…' : 'PDF da proposta',
              busy: _pdfLoading,
              onTap: _pdfLoading ? null : () => _abrirPdf(),
            ),
            // PDF gerado + o(s) assinado(s) do Autentique num .zip (o web
            // entrega isso no download; padrão `incluirAutentique` do back).
            if (_etapaTemAssinado)
              _AcaoTexto(
                icon: LucideIcons.fileArchive,
                label: 'PDF + assinado (.zip)',
                busy: _pdfLoading,
                onTap: _pdfLoading ? null : () => _abrirPdf(comAssinado: true),
              ),
            if (_alreadySent)
              _AcaoTexto(
                icon: LucideIcons.refreshCw,
                label: _syncing ? 'Verificando…' : 'Verificar assinaturas',
                busy: _syncing,
                onTap: _syncing || _loading ? null : _sync,
              ),
            if (_etapasDisponiveis.isNotEmpty)
              _AcaoTexto(
                icon: LucideIcons.paperclip,
                label: _uploading ? 'Enviando…' : 'Anexar ficha física',
                color: _green,
                busy: _uploading,
                onTap: _uploading ? null : _anexarFicha,
              ),
          ],
        ),
        if (_etapasDisponiveis.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'A ficha física anexada dispensa a assinatura digital da etapa.',
              style: t.labelSmall?.copyWith(color: muted, height: 1.3),
            ),
          ),
        if (_alreadySent) ...[
          const SizedBox(height: 20),
          _SectionLabel(
            'SIGNATÁRIOS DA ETAPA $_etapa',
            accent: _accent,
            trailing: daEtapa.isEmpty
                ? null
                : '$assinadas de ${daEtapa.length} '
                    '${daEtapa.length == 1 ? 'assinou' : 'assinaram'}',
          ),
          const SizedBox(height: 2),
          if (daEtapa.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                mostrarForm
                    ? 'Ninguém recebeu esta etapa ainda. Preencha abaixo e '
                        'envie.'
                    : 'Ninguém recebeu esta etapa para assinar ainda.',
                style: t.bodySmall?.copyWith(color: muted, height: 1.35),
              ),
            )
          else
            for (final s in daEtapa)
              _SignatureRow(
                signature: s,
                ehVoce: _ehVoce(s.signerEmail),
                busy: _linkBusyId == s.id,
                temLink: _urls.containsKey(s.id),
                encerrada: _encerrada(s),
                green: _green,
                warn: _warnText,
                red: _red,
                blue: _blue,
                accent: _accent,
                onAssinar: () => _assinar(s),
                onCopyLink: () => _copiarLink(s),
                onWhatsapp: () => _whatsapp(s),
                onResendEmail: canUpdate &&
                        (s.signerEmail?.trim().isNotEmpty ?? false)
                    ? () => _reenviarEmail(s)
                    : null,
                onResendWhatsapp: canUpdate &&
                        (_waEnvio?.canResend ?? false) &&
                        _urls.containsKey(s.id)
                    ? () => _reenviarWhatsapp(s)
                    : null,
              ),
        ],
        if (mostrarForm) ...[
          const SizedBox(height: 24),
          _SectionLabel('ENVIAR — ETAPA $_etapa', accent: _accent),
          const SizedBox(height: 12),
          TextField(
            controller: _docName,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_docNameTouched) setState(() {});
            },
            decoration: _filledDecoration(
              context,
              label: 'Nome do documento *',
              error: nomeVazio ? 'Nome do documento é obrigatório.' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _docMessage,
            minLines: 2,
            maxLines: 4,
            decoration: _filledDecoration(
              context,
              label: 'Mensagem ao signatário (opcional)',
              hint: 'Por favor, assine este documento.',
              alignLabel: true,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Como enviar — vale para todos os signatários',
            style: t.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 8),
          _ModoEnvio(
            porEmail: _porEmail,
            accent: _accent,
            onChanged: (v) => setState(() => _porEmail = v),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _forms.length; i++)
            _SignerFormRow(
              index: i,
              form: _forms[i],
              porEmail: _porEmail,
              onRemove: _forms.length > 1
                  ? () => setState(() => _forms.removeAt(i).dispose())
                  : null,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _forms.add(_SignerForm())),
              icon: const Icon(LucideIcons.plus, size: 17),
              label: const Text('Adicionar signatário'),
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                minimumSize: const Size(48, 44),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Web: `AutentiqueSendGate` — integração inativa trava o envio
          // e diz o porquê.
          if (_autentiqueBlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InfoLine(
                icon: LucideIcons.lock,
                color: _red,
                text: kAutentiqueInactiveMessage,
              ),
            ),
          FilledButton.icon(
            onPressed: _sending || _autentiqueBlocked ? null : _enviar,
            icon: _sending
                ? const _Spin(color: Colors.white)
                : Icon(
                    _porEmail ? LucideIcons.send : LucideIcons.link,
                    size: 18,
                  ),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _sending
                    ? 'Enviando…'
                    : _porEmail
                        ? 'Enviar por e-mail'
                        : 'Gerar link',
                maxLines: 1,
                softWrap: false,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _green.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ] else if (canUpdate && daEtapa.any(_assinada)) ...[
          const SizedBox(height: 16),
          _InfoLine(
            icon: LucideIcons.circleCheck,
            color: _green,
            text: 'Esta etapa já tem assinatura concluída, por isso não há '
                'novo envio aqui.',
          ),
        ] else if (!canUpdate && _mostrarFormulario) ...[
          const SizedBox(height: 18),
          _InfoLine(
            icon: LucideIcons.lock,
            color: muted,
            text: 'Enviar para assinatura está travado: sua conta não edita '
                'propostas. Peça ao administrador a permissão de edição.',
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_loading && _historico == null) return _skeleton();
    final h = _historico;
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (h == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        children: [
          AppErrorState.fromApi(
            message: _error ?? 'Histórico indisponível no momento.',
            statusCode: _errorStatus,
            onRetry: _load,
            dense: true,
          ),
        ],
      );
    }
    final events = [...h.stageHistory]..sort(
        (a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)),
      );
    final atts = h.attachments;
    return RefreshIndicator(
      onRefresh: _load,
      color: _accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SectionLabel('ANEXOS FÍSICOS', accent: _accent),
          const SizedBox(height: 4),
          if (atts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nenhuma ficha física anexada. Quando o cliente assinar no '
                'papel, use "Anexar ficha física" na aba Assinaturas.',
                style: t.bodySmall?.copyWith(color: muted, height: 1.35),
              ),
            )
          else
            for (final a in atts)
              _AttachmentRow(
                att: a,
                label: _etapaLabel(a.etapa),
                green: _green,
                red: _red,
                warn: _warnText,
                onApprove: _podeDecidirAnexo(a) ? () => _aprovarAnexo(a) : null,
                onReject: _podeDecidirAnexo(a) ? () => _rejeitarAnexo(a) : null,
              ),
          // Web: no histórico, cada etapa lista as assinaturas com o status
          // (e o motivo da recusa) — `ProposalSignaturesModalPrivate:616`.
          for (final etapaNum in const [1, 2, 3])
            if (h.signatures.any((s) => s.etapa == etapaNum)) ...[
              const SizedBox(height: 20),
              _SectionLabel(
                'ASSINATURAS · ETAPA $etapaNum · '
                '${_etapaLabel(etapaNum).toUpperCase()}',
                accent: _accent,
              ),
              const SizedBox(height: 4),
              for (final s in h.signatures.where((s) => s.etapa == etapaNum))
                _HistSignatureRow(
                  signature: s,
                  green: _green,
                  red: _red,
                  warn: _warnText,
                  blue: _blue,
                ),
            ],
          const SizedBox(height: 20),
          _SectionLabel('EVENTOS', accent: _accent),
          const SizedBox(height: 4),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nenhum evento ainda. Envios e assinaturas aparecem aqui, do '
                'mais recente para o mais antigo.',
                style: t.bodySmall?.copyWith(color: muted, height: 1.35),
              ),
            )
          else
            for (final e in events) _EventRow(event: e),
        ],
      ),
    );
  }
}

// ─── Peças ────────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.proposalNumber,
    required this.titulo,
    required this.onClose,
    this.compacto = false,
  });

  final String proposalNumber;
  final String titulo;
  final VoidCallback onClose;

  /// Teclado aberto: só a linha do título + fechar (sem alça e sem rótulo).
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final numero = proposalNumber.trim().isEmpty
        ? 'Proposta sem número'
        : 'Proposta nº $proposalNumber';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        compacto ? 4.0 : 10.0,
        8,
        compacto ? 0.0 : 4.0,
      ),
      child: Column(
        children: [
          if (!compacto)
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compacto)
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                      ),
                    Text(
                      numero,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: onClose,
                icon: Icon(LucideIcons.x, size: 20, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.accent, this.trailing});
  final String text;
  final Color accent;

  /// Resumo curto à direita (ex.: "1 de 2 assinaram").
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 11,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(
            trailing!,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
          ),
        ],
      ],
    );
  }
}

/// Etapas como abas com sublinhado. Etapa ainda fechada mostra cadeado e,
/// ao toque, o motivo ([onLocked]) — travada, não escondida.
class _EtapaPicker extends StatelessWidget {
  const _EtapaPicker({
    required this.current,
    required this.maxLiberada,
    required this.accent,
    required this.onChanged,
    required this.onLocked,
  });

  final int current;
  final int maxLiberada;
  final Color accent;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onLocked;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 1; i <= 3; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: current == i,
              label: i <= maxLiberada
                  ? 'Etapa $i'
                  : 'Etapa $i, bloqueada até concluir a etapa ${i - 1}',
              child: InkWell(
                onTap: i <= maxLiberada
                    ? () => onChanged(i)
                    : () => onLocked(i),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: current == i
                            ? accent
                            : ThemeHelpers.borderLightColor(context),
                        width: current == i ? 2.5 : 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (i > maxLiberada) ...[
                            Icon(LucideIcons.lock, size: 11, color: muted),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              'ETAPA $i',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelSmall?.copyWith(
                                color: current == i ? accent : muted,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        switch (i) {
                          1 => 'Comprador',
                          2 => 'Proprietário',
                          _ => 'Corretor',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: i > maxLiberada
                              ? muted.withValues(alpha: 0.7)
                              : ThemeHelpers.textColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AcaoTexto extends StatelessWidget {
  const _AcaoTexto({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: busy ? const _Spin() : Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        foregroundColor: color ?? ThemeHelpers.textColor(context),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

class _VoceBadge extends StatelessWidget {
  const _VoceBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'VOCÊ',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

/// Linha de signatário: quem (iniciais, nome, e-mail), estado (pílula com
/// ícone + rótulo, e quando) e as ações à vista — copiar link e WhatsApp
/// no próprio item, reenvios num menu "Reenviar". "Você" ganha "Assinar".
class _SignatureRow extends StatelessWidget {
  const _SignatureRow({
    required this.signature,
    required this.ehVoce,
    required this.busy,
    required this.temLink,
    required this.encerrada,
    required this.green,
    required this.warn,
    required this.red,
    required this.blue,
    required this.accent,
    required this.onAssinar,
    required this.onCopyLink,
    required this.onWhatsapp,
    this.onResendEmail,
    this.onResendWhatsapp,
  });

  final ProposalSignature signature;
  final bool ehVoce;
  final bool busy;
  final bool temLink;
  final bool encerrada;
  final Color green;

  /// Âmbar de texto (pendente).
  final Color warn;
  final Color red;
  final Color blue;
  final Color accent;
  final VoidCallback onAssinar;
  final VoidCallback onCopyLink;
  final VoidCallback onWhatsapp;
  final VoidCallback? onResendEmail;
  final VoidCallback? onResendWhatsapp;

  static final DateFormat _fmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  String get _st => signature.status.toLowerCase();

  Color _tone(BuildContext context) {
    switch (_st) {
      case 'signed':
      case 'approved':
        return green;
      case 'rejected':
        return red;
      case 'cancelled':
      case 'canceled':
        return ThemeHelpers.textSecondaryColor(context);
      case 'viewed':
        return blue;
      default:
        return warn;
    }
  }

  IconData get _icon {
    switch (_st) {
      case 'signed':
      case 'approved':
        return LucideIcons.circleCheck;
      case 'rejected':
        return LucideIcons.circleX;
      case 'cancelled':
      case 'canceled':
        return LucideIcons.ban;
      case 'viewed':
        return LucideIcons.eye;
      default:
        return LucideIcons.clock;
    }
  }

  /// Rótulo do web (uma fonte só: `ProposalSignature.statusLabel`).
  String get _label => signature.statusLabel;

  /// Quando: assinatura > visualização > envio (o que houver).
  String? get _quando {
    final signedAt = signature.signedAt;
    if (signedAt != null) return 'em ${_fmt.format(signedAt.toLocal())}';
    final viewedAt = signature.viewedAt;
    if (viewedAt != null) {
      return 'abriu em ${_fmt.format(viewedAt.toLocal())}';
    }
    final createdAt = signature.createdAt;
    if (createdAt != null) {
      return 'enviado em ${_fmt.format(createdAt.toLocal())}';
    }
    return null;
  }

  String _iniciais(String nome) {
    final parts = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && p[0] != '@')
        .toList();
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = _tone(context);
    final email = signature.signerEmail?.trim() ?? '';
    final temEmail = email.isNotEmpty;
    final nomeInformado = signature.signerName?.trim() ?? '';
    final nome = nomeInformado.isNotEmpty
        ? nomeInformado
        : (temEmail ? email : 'Signatário sem nome');
    final quando = _quando;
    final motivo = signature.rejectionReason?.trim();
    final podeReenviar = onResendEmail != null || onResendWhatsapp != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? AppColors.background.backgroundTertiaryDarkMode
                      : AppColors.background.backgroundTertiary,
                ),
                child: Text(
                  _iniciais(nome),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (ehVoce) ...[
                          const SizedBox(width: 6),
                          _VoceBadge(color: accent),
                        ],
                      ],
                    ),
                    if (temEmail && nome != email)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: muted),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SignerStatusPill(
                          label: _label,
                          icon: _icon,
                          tone: tone,
                        ),
                        if (quando != null)
                          Text(
                            quando,
                            maxLines: 1,
                            style: t.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (motivo != null && motivo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Motivo: $motivo',
                          style: t.bodySmall?.copyWith(
                            color: red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!encerrada) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ehVoce)
                    FilledButton.icon(
                      onPressed: busy ? null : onAssinar,
                      icon: const Icon(LucideIcons.penLine, size: 16),
                      label: const Text('Assinar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  _RowAction(
                    icon: LucideIcons.copy,
                    label: temLink ? 'Copiar link' : 'Gerar e copiar link',
                    busy: busy,
                    onTap: busy ? null : onCopyLink,
                  ),
                  _RowAction(
                    icon: LucideIcons.messageCircle,
                    label: 'WhatsApp',
                    onTap: busy ? null : onWhatsapp,
                  ),
                  if (podeReenviar)
                    PopupMenuButton<String>(
                      tooltip: 'Reenviar',
                      enabled: !busy,
                      color: ThemeHelpers.cardBackgroundColor(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      itemBuilder: (ctx) => [
                        if (onResendEmail != null)
                          const PopupMenuItem(
                            value: 'email',
                            child: Text('Reenviar e-mail'),
                          ),
                        if (onResendWhatsapp != null)
                          const PopupMenuItem(
                            value: 'resend',
                            child: Text('Reenviar pelo WhatsApp da empresa'),
                          ),
                      ],
                      onSelected: (v) {
                        if (v == 'email') {
                          onResendEmail?.call();
                        } else if (v == 'resend') {
                          onResendWhatsapp?.call();
                        }
                      },
                      child: const _RowAction(
                        icon: LucideIcons.rotateCw,
                        label: 'Reenviar',
                        trailing: LucideIcons.chevronDown,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pílula de estado do signatário: ícone + rótulo (nunca só a cor).
class _SignerStatusPill extends StatelessWidget {
  const _SignerStatusPill({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

/// Ação curta da linha (contorno neutro). Sem [onTap] vira só o visual —
/// usado dentro do menu "Reenviar".
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.busy = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final visual = Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          busy ? const _Spin() : Icon(icon, size: 15, color: muted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(trailing, size: 14, color: muted),
          ],
        ],
      ),
    );
    if (onTap == null && trailing != null) return visual;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: visual,
      ),
    );
  }
}

/// Aviso de uma linha com ícone (concluído, travado por permissão…).
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.att,
    required this.label,
    required this.green,
    required this.red,
    required this.warn,
    this.onApprove,
    this.onReject,
  });

  final ProposalAttachment att;
  final String label;
  final Color green;
  final Color red;

  /// Âmbar de texto (aguardando aprovação).
  final Color warn;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final st = att.status.toLowerCase();
    final tone = st == 'approved'
        ? green
        : st == 'rejected'
            ? red
            : warn;
    final statusLabel = st == 'approved'
        ? 'Aprovado'
        : st == 'rejected'
            ? 'Rejeitado'
            : 'Aguardando aprovação';
    final statusIcon = st == 'approved'
        ? LucideIcons.circleCheck
        : st == 'rejected'
            ? LucideIcons.circleX
            : LucideIcons.clock;
    final canOpen = att.fileUrl.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'ETAPA ${att.etapa} · ${label.toUpperCase()}',
                maxLines: 1,
                style: t.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _SignerStatusPill(
                label: statusLabel,
                icon: statusIcon,
                tone: tone,
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: canOpen
                ? () async {
                    final uri = Uri.tryParse(att.fileUrl);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(LucideIcons.paperclip, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      att.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (canOpen) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.externalLink, size: 15, color: muted),
                  ],
                ],
              ),
            ),
          ),
          Text(
            [
              if (att.uploadedByName?.isNotEmpty == true)
                'Enviado por ${att.uploadedByName}',
              if (att.createdAt != null)
                DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                    .format(att.createdAt!.toLocal()),
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(color: muted),
          ),
          if (att.rejectionReason?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Motivo: ${att.rejectionReason}',
                style: t.bodySmall?.copyWith(color: red),
              ),
            ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: red,
                        minimumSize: const Size(48, 44),
                        side: BorderSide(color: red.withValues(alpha: 0.45)),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Rejeitar', maxLines: 1),
                      ),
                    ),
                  ),
                if (onReject != null && onApprove != null)
                  const SizedBox(width: 10),
                if (onApprove != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 44),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Aprovar', maxLines: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Assinatura no histórico: quem, status (rótulo do web), quando e o motivo
/// da recusa.
class _HistSignatureRow extends StatelessWidget {
  const _HistSignatureRow({
    required this.signature,
    required this.green,
    required this.red,
    required this.warn,
    required this.blue,
  });

  final ProposalSignature signature;
  final Color green;
  final Color red;
  final Color warn;
  final Color blue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final st = signature.status.trim().toLowerCase();
    final (Color tone, IconData icon) = switch (st) {
      'signed' || 'approved' => (green, LucideIcons.circleCheck),
      'rejected' => (red, LucideIcons.circleX),
      'viewed' => (blue, LucideIcons.eye),
      'cancelled' || 'canceled' => (muted, LucideIcons.ban),
      _ => (warn, LucideIcons.clock),
    };
    final nome = (signature.signerName?.trim().isNotEmpty ?? false)
        ? signature.signerName!.trim()
        : (signature.signerEmail?.trim().isNotEmpty ?? false)
            ? signature.signerEmail!.trim()
            : '—';
    final email = signature.signerEmail?.trim() ?? '';
    final quando = signature.signedAt ?? signature.createdAt;
    final motivo = signature.rejectionReason?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (email.isNotEmpty && email != nome)
            Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: muted),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SignerStatusPill(
                label: signature.statusLabel,
                icon: icon,
                tone: tone,
              ),
              if (quando != null)
                Text(
                  DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                      .format(quando.toLocal()),
                  style: t.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (st == 'rejected' && motivo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Motivo da recusa: $motivo',
                style: t.bodySmall?.copyWith(color: red),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final ProposalHistoryEvent event;

  /// Nome do evento em português; tipo desconhecido vira frase legível
  /// ("etapa_2_liberada" → "Etapa 2 liberada"), nunca o código cru.
  static String _nome(String type) {
    final known = _kEventLabels[type];
    if (known != null) return known;
    final s = type.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (s.isEmpty) return 'Evento';
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final quando = event.createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
            .format(event.createdAt!.toLocal())
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.circleDot, size: 14, color: muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nome(event.eventType),
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Etapa ${event.etapa}',
                    if (quando != null) quando,
                  ].join(' · '),
                  style: t.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _kAnexoExtensoes = ['pdf', 'jpg', 'jpeg', 'png', 'webp'];

class _SignerForm {
  _SignerForm({String name = '', String email = ''})
      : name = TextEditingController(text: name),
        email = TextEditingController(text: email);

  final TextEditingController name;
  final TextEditingController email;

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

/// Campo `filled` da casa: fundo terciário, filete leve em repouso, foco na
/// cor da marca, erro em vermelho.
InputDecoration _filledDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? error,
  bool alignLabel = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final accent =
      dark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  final danger = dark ? AppColors.status.errorDarkMode : AppColors.status.error;
  final fill = dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;
  final radius = BorderRadius.circular(12);
  OutlineInputBorder line(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    alignLabelWithHint: alignLabel,
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: line(ThemeHelpers.borderLightColor(context)),
    enabledBorder: line(ThemeHelpers.borderLightColor(context)),
    focusedBorder: line(accent, 1.6),
    errorBorder: line(danger),
    focusedErrorBorder: line(danger, 1.6),
  );
}

/// Modo de envio (vale para todos os signatários): dois cartões lado a lado
/// com o que cada um faz — escolha com consequência explicada.
class _ModoEnvio extends StatelessWidget {
  const _ModoEnvio({
    required this.porEmail,
    required this.accent,
    required this.onChanged,
  });

  final bool porEmail;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _opcao(
              context,
              valor: true,
              icon: LucideIcons.mail,
              titulo: 'Enviar por e-mail',
              explica: 'Cada signatário recebe o convite no e-mail.',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _opcao(
              context,
              valor: false,
              icon: LucideIcons.link,
              titulo: 'Gerar apenas link',
              explica: 'Só o nome; você manda o link por WhatsApp ou cópia.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _opcao(
    BuildContext context, {
    required bool valor,
    required IconData icon,
    required String titulo,
    required String explica,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ativo = porEmail == valor;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? accent.withValues(alpha: isDark ? 0.16 : 0.08) : fill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onChanged(valor),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ativo ? accent : ThemeHelpers.borderLightColor(context),
                width: ativo ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 17, color: ativo ? accent : muted),
                    const Spacer(),
                    Icon(
                      ativo
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: ativo ? accent : muted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: ativo ? accent : ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  explica,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: muted,
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

class _SignerFormRow extends StatelessWidget {
  const _SignerFormRow({
    required this.index,
    required this.form,
    required this.porEmail,
    this.onRemove,
  });

  final int index;
  final _SignerForm form;
  final bool porEmail;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final nome = TextField(
      controller: form.name,
      textCapitalization: TextCapitalization.words,
      textInputAction: porEmail ? TextInputAction.next : TextInputAction.done,
      decoration: _filledDecoration(
        context,
        label: porEmail ? 'Nome do signatário' : 'Nome do signatário *',
      ),
    );
    final email = TextField(
      controller: form.email,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: _filledDecoration(
        context,
        label: 'E-mail *',
        hint: 'email@exemplo.com',
      ),
    );
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Signatário ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remover signatário',
                  onPressed: onRemove,
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 17,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                )
              else
                const SizedBox(height: 40),
            ],
          ),
          // Duas colunas quando cabe (tablet/paisagem); empilha no celular.
          LayoutBuilder(
            builder: (context, c) {
              if (porEmail && c.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nome),
                    const SizedBox(width: 10),
                    Expanded(child: email),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nome,
                  if (porEmail) ...[
                    const SizedBox(height: 10),
                    email,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
