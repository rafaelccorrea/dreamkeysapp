import 'dart:io' show File, Directory;
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
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/services/sale_forms_service.dart'
    show saleFormLinkAbrivel, saleFormSignerExcluido;
import '../../../shared/widgets/skeleton_box.dart';

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
  bool _sending = false;
  bool _syncing = false;
  bool _uploading = false;
  bool _pdfLoading = false;
  String? _linkBusyId;

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
  Color get _warn =>
      _isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
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
    final histRes = await histFut;
    final sigs = await sigsFut;
    final propRes = await propFut;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (histRes.success && histRes.data != null) {
        _historico = histRes.data;
      } else {
        _error = histRes.message;
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      _snack(_porEmail
          ? 'Proposta enviada para assinatura.'
          : 'Envio criado. Use Copiar link ou WhatsApp para cada signatário '
              'na lista.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao enviar para assinatura.');
    }
  }

  Future<void> _abrirPdf() async {
    setState(() => _pdfLoading = true);
    final res = await PurchaseProposalsService.instance.downloadPdf(
      widget.proposalId,
      etapa: _etapa,
    );
    if (!mounted) return;
    setState(() => _pdfLoading = false);
    if (!res.success || res.data == null) {
      _snack(res.message ?? 'Erro ao carregar PDF.');
      return;
    }
    try {
      final bytes = res.data!.bytes;
      final dir = Directory.systemTemp;
      final ext = res.data!.contentType.contains('zip') ? 'zip' : 'pdf';
      final file = File(
          '${dir.path}/proposta_${_proposalNumber}_etapa$_etapa.$ext');
      await file.writeAsBytes(bytes);
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _snack('PDF salvo em ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao abrir PDF: $e');
    }
  }

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

  Future<void> _reenviarWhatsapp(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance
        .reenviarUmWhatsapp(widget.proposalId, sig.id);
    if (!mounted) return;
    _snack(res.success
        ? 'Reenvio pelo WhatsApp iniciado.'
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
      _snack(approved
          ? 'Ficha anexada. Etapa ${_etapaLabel(etapa)} liberada.'
          : 'Ficha anexada. Aguardando aprovação do gestor.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao anexar ficha.');
    }
  }

  Future<int?> _escolherEtapa(List<int> etapas) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
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
    );
  }

  Future<void> _aprovarAnexo(ProposalAttachment att) async {
    final res = await PurchaseProposalsService.instance
        .aprovarAnexo(widget.proposalId, att.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Anexo aprovado.');
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
          decoration: const InputDecoration(
            labelText: 'Motivo da rejeição *',
            hintText: 'Explique por que a ficha não foi aceita',
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
    final altura = math.min(
      mq.size.height * 0.88,
      mq.size.height - mq.viewInsets.bottom - mq.padding.top - 12,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: altura,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            _SheetHeader(
              proposalNumber: _proposalNumber,
              titulo: 'ASSINATURAS · ${_etapaLabel(_etapa).toUpperCase()}',
              onClose: () => Navigator.of(context).pop(),
            ),
            TabBar(
              controller: _tab,
              indicatorColor: _accent,
              labelColor: _accent,
              unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
              tabs: const [
                Tab(text: 'Assinaturas'),
                Tab(text: 'Histórico'),
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
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const SkeletonBox(height: 52, borderRadius: 12),
        const SizedBox(height: 18),
        for (var i = 0; i < 4; i++) ...[
          const SkeletonBox(height: 54, borderRadius: 10),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSendTab({required bool canUpdate}) {
    if (_loading && _historico == null) return _skeleton();
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (_error != null && _historico == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    final daEtapa = _daEtapa;
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
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _AcaoTexto(
              icon: LucideIcons.fileText,
              label: _pdfLoading ? 'Carregando PDF…' : 'PDF da proposta',
              busy: _pdfLoading,
              onTap: _pdfLoading ? null : _abrirPdf,
            ),
            if (_alreadySent)
              _AcaoTexto(
                icon: LucideIcons.refreshCw,
                label: _syncing ? 'Verificando…' : 'Verificar',
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
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A ficha física anexada dispensa a assinatura digital da etapa.',
              style: t.labelSmall?.copyWith(color: muted),
            ),
          ),
        if (_alreadySent) ...[
          const SizedBox(height: 18),
          _SectionLabel('STATUS DAS ASSINATURAS', accent: _accent),
          const SizedBox(height: 4),
          if (daEtapa.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum signatário nesta etapa. Adicione abaixo e envie.',
                style: t.bodySmall?.copyWith(color: muted),
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
                warn: _warn,
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
                onResendWhatsapp:
                    canUpdate ? () => _reenviarWhatsapp(s) : null,
              ),
        ],
        if (mostrarForm) ...[
          const SizedBox(height: 22),
          _SectionLabel('ENVIAR — ETAPA $_etapa', accent: _accent),
          const SizedBox(height: 10),
          TextField(
            controller: _docName,
            onChanged: (_) {
              if (_docNameTouched) setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Nome do documento *',
              border: const OutlineInputBorder(),
              errorText: nomeVazio ? 'Nome do documento é obrigatório.' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _docMessage,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Mensagem ao signatário (opcional)',
              hintText: 'Por favor, assine este documento.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'O modo abaixo vale para todos os signatários.',
            style: t.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(LucideIcons.mail, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Enviar por e-mail'),
                ),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(LucideIcons.link, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Gerar apenas link'),
                ),
              ),
            ],
            selected: {_porEmail},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _porEmail = v.first),
          ),
          const SizedBox(height: 6),
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
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _enviar,
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
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ] else if (canUpdate && daEtapa.any(_assinada)) ...[
          const SizedBox(height: 16),
          Text(
            'Esta etapa já tem assinatura concluída.',
            style: t.bodySmall?.copyWith(color: muted),
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
      return Center(
        child: Text(
          'Histórico indisponível.',
          style: t.bodySmall?.copyWith(color: muted),
        ),
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
                'Sem anexos.',
                style: t.bodySmall?.copyWith(color: muted),
              ),
            )
          else
            for (final a in atts)
              _AttachmentRow(
                att: a,
                label: _etapaLabel(a.etapa),
                green: _green,
                red: _red,
                warn: _warn,
                onApprove:
                    _isGestor && a.status.toLowerCase() == 'pending_approval'
                        ? () => _aprovarAnexo(a)
                        : null,
                onReject:
                    _isGestor && a.status.toLowerCase() == 'pending_approval'
                        ? () => _rejeitarAnexo(a)
                        : null,
              ),
          const SizedBox(height: 20),
          _SectionLabel('EVENTOS', accent: _accent),
          const SizedBox(height: 4),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nenhum evento registrado.',
                style: t.bodySmall?.copyWith(color: muted),
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
  });

  final String proposalNumber;
  final String titulo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                    ),
                    Text(
                      'Proposta nº $proposalNumber',
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
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.accent});
  final String text;
  final Color accent;

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
      ],
    );
  }
}

class _EtapaPicker extends StatelessWidget {
  const _EtapaPicker({
    required this.current,
    required this.maxLiberada,
    required this.accent,
    required this.onChanged,
  });

  final int current;
  final int maxLiberada;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 1; i <= 3; i++)
          Expanded(
            child: InkWell(
              onTap: i <= maxLiberada ? () => onChanged(i) : null,
              child: Tooltip(
                message: i <= maxLiberada
                    ? ''
                    : 'Conclua a Etapa ${i - 1} antes.',
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: current == i
                            ? accent
                            : ThemeHelpers.borderLightColor(context),
                        width: current == i ? 2 : 1,
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
                              ? muted.withValues(alpha: 0.6)
                              : null,
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
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color ?? ThemeHelpers.textColor(context),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  final Color warn;
  final Color red;
  final Color blue;
  final Color accent;
  final VoidCallback onAssinar;
  final VoidCallback onCopyLink;
  final VoidCallback onWhatsapp;
  final VoidCallback? onResendEmail;
  final VoidCallback? onResendWhatsapp;

  Color _tone(BuildContext context) {
    switch (signature.status.toLowerCase()) {
      case 'signed':
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

  String get _label {
    switch (signature.status.toLowerCase()) {
      case 'signed':
        return 'Assinado';
      case 'rejected':
        return 'Rejeitado';
      case 'viewed':
        return 'Visualizado';
      case 'approved':
        return 'Aprovado';
      case 'cancelled':
      case 'canceled':
        return 'Cancelado';
      default:
        return 'Pendente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = _tone(context);
    final nome = signature.signerName?.trim().isNotEmpty == true
        ? signature.signerName!.trim()
        : (signature.signerEmail ?? '—');
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  signature.signerEmail != null
                      ? LucideIcons.mail
                      : LucideIcons.userCheck,
                  size: 16,
                  color: tone,
                ),
              ),
              const SizedBox(width: 10),
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
                    if (signature.signerEmail != null)
                      Text(
                        signature.signerEmail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: muted),
                      ),
                    if (signature.signedAt != null)
                      Text(
                        'Assinado em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(signature.signedAt!.toLocal())}',
                        style: t.labelSmall?.copyWith(color: green),
                      ),
                    if (signature.rejectionReason != null)
                      Text(
                        'Motivo: ${signature.rejectionReason}',
                        style: t.bodySmall?.copyWith(color: red),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _label.toUpperCase(),
                style: t.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              if (!encerrada)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Ações',
                  icon: busy
                      ? const _Spin()
                      : Icon(LucideIcons.ellipsisVertical,
                          size: 18, color: muted),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text(temLink ? 'Copiar link' : 'Gerar e copiar link'),
                    ),
                    const PopupMenuItem(
                      value: 'wa',
                      child: Text('Compartilhar no WhatsApp'),
                    ),
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
                    switch (v) {
                      case 'copy':
                        onCopyLink();
                        break;
                      case 'wa':
                        onWhatsapp();
                        break;
                      case 'email':
                        onResendEmail?.call();
                        break;
                      case 'resend':
                        onResendWhatsapp?.call();
                        break;
                    }
                  },
                ),
            ],
          ),
          if (ehVoce && !encerrada) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: FilledButton.icon(
                onPressed: busy ? null : onAssinar,
                icon: const Icon(LucideIcons.penLine, size: 16),
                label: const Text('Assinar'),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
    final canOpen = att.fileUrl.isNotEmpty;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'ETAPA ${att.etapa} · ${label.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                statusLabel.toUpperCase(),
                style: t.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
            child: Row(
              children: [
                Icon(LucideIcons.paperclip, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    att.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (canOpen) ...[
                  const SizedBox(width: 6),
                  Icon(LucideIcons.externalLink, size: 15, color: muted),
                ],
              ],
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
                        side: BorderSide(color: red.withValues(alpha: 0.45)),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Rejeitar'),
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
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Aprovar'),
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

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final ProposalHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              'E${event.etapa}',
              style: t.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: muted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kEventLabels[event.eventType] ?? event.eventType,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (event.createdAt != null)
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(event.createdAt!.toLocal()),
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
    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              IconButton(
                tooltip: 'Remover',
                onPressed: onRemove,
                icon: const Icon(LucideIcons.trash2, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          TextField(
            controller: form.name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: porEmail ? 'Nome do signatário' : 'Nome do signatário *',
              border: const OutlineInputBorder(),
            ),
          ),
          if (porEmail) ...[
            const SizedBox(height: 10),
            TextField(
              controller: form.email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail *',
                hintText: 'email@exemplo.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
