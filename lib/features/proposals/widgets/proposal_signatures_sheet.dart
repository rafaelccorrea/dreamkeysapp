import 'dart:io' show File, Directory;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';

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

class _ProposalSignaturesSheetState extends State<_ProposalSignaturesSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  ProposalHistorico? _historico;
  List<ProposalSignature> _signatures = const [];
  String? _error;
  bool _sending = false;
  bool _syncing = false;
  bool _uploading = false;

  final ImagePicker _imagePicker = ImagePicker();

  late int _etapa;
  late final List<_SignerForm> _forms = [];

  @override
  void initState() {
    super.initState();
    _etapa = widget.etapa;
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialHistorico ? 1 : 0,
    );
    for (final s in widget.defaultSigners) {
      _forms.add(_SignerForm.fromInput(s));
    }
    if (_forms.isEmpty) {
      _forms.add(_SignerForm());
    }
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final histFut = PurchaseProposalsService.instance
        .getHistorico(widget.proposalId);
    final sigsFut = PurchaseProposalsService.instance
        .listSignatures(widget.proposalId);
    final histRes = await histFut;
    final sigsRes = await sigsFut;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (histRes.success && histRes.data != null) {
        _historico = histRes.data;
      } else {
        _error = histRes.message;
      }
      if (sigsRes.success && sigsRes.data != null) {
        _signatures = sigsRes.data!;
      }
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final res = await PurchaseProposalsService.instance
        .syncAssinaturas(widget.proposalId);
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() {
        _signatures = res.data!;
        _syncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assinaturas sincronizadas.')),
      );
      widget.onChanged?.call();
      _load();
    } else {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao sincronizar.')),
      );
    }
  }

  Future<void> _enviar() async {
    final valid = _forms.where((f) => f.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe pelo menos um signatário (nome + e-mail).'),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    final res = await PurchaseProposalsService.instance.enviarParaAssinatura(
      widget.proposalId,
      signers: valid.map((f) => f.toInput()).toList(),
      etapa: _etapa,
      documentName: 'Proposta ${widget.proposalNumber} - Etapa $_etapa',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enviado para assinatura.')),
      );
      widget.onChanged?.call();
      _tab.animateTo(1);
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao enviar.')),
      );
    }
  }

  Future<void> _abrirPdf() async {
    final res = await PurchaseProposalsService.instance.downloadPdf(
      widget.proposalId,
      etapa: _etapa,
    );
    if (!mounted) return;
    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao baixar PDF.')),
      );
      return;
    }
    // Salvar em ficheiro temporário e tentar abrir.
    try {
      final bytes = res.data!.bytes;
      final dir = Directory.systemTemp;
      final ext = res.data!.contentType.contains('zip') ? 'zip' : 'pdf';
      final file = File(
          '${dir.path}/proposta_${widget.proposalNumber}_etapa$_etapa.$ext');
      await file.writeAsBytes(bytes);
      final uri = Uri.file(file.path);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF salvo em ${file.path}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir PDF: $e')),
      );
    }
  }

  Future<void> _copiarLink(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance.obterLinkAssinatura(
      widget.proposalId,
      sig.id,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      await Clipboard.setData(ClipboardData(text: res.data!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copiado para a área de transferência.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao obter link.')),
      );
    }
  }

  Future<void> _abrirLink(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance.obterLinkAssinatura(
      widget.proposalId,
      sig.id,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final uri = Uri.tryParse(res.data!);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao obter link.')),
      );
    }
  }

  Future<void> _reenviarEmail(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance
        .reenviarPorEmail(widget.proposalId, sig.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.success
              ? 'E-mail reenviado.'
              : res.message ?? 'Erro ao reenviar e-mail.',
        ),
      ),
    );
  }

  Future<void> _reenviarWhatsapp(ProposalSignature sig) async {
    final res = await PurchaseProposalsService.instance
        .reenviarUmWhatsapp(widget.proposalId, sig.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.success
              ? 'Reenvio WhatsApp iniciado.'
              : res.message ?? 'Erro ao reenviar via WhatsApp.',
        ),
      ),
    );
  }

  bool get _isGestor {
    final role = ModuleAccessService.instance.userRole?.toLowerCase();
    return role == 'manager' || role == 'admin' || role == 'master';
  }

  /// Etapas em que ainda é permitido anexar a ficha física: liberadas para
  /// envio (<= maxEtapaLiberadaParaEnvio) e ainda não concluídas por
  /// assinatura registrada ou anexo já aprovado.
  List<int> get _etapasDisponiveis {
    final h = _historico;
    final max = h?.maxEtapaLiberadaParaEnvio ?? _etapa;
    final concluidas = <int>{};
    for (final s in [..._signatures, ...?h?.signatures]) {
      if (s.status.toLowerCase() == 'signed') concluidas.add(s.etapa);
    }
    for (final a in h?.attachments ?? const <ProposalAttachment>[]) {
      if (a.status.toLowerCase() == 'approved') concluidas.add(a.etapa);
    }
    final out = <int>[];
    for (var i = 1; i <= max && i <= 3; i++) {
      if (!concluidas.contains(i)) out.add(i);
    }
    return out;
  }

  String _etapaLabel(int etapa) => switch (etapa) {
        1 => 'Comprador',
        2 => 'Proprietário',
        _ => 'Corretor',
      };

  Future<void> _anexarFicha() async {
    final etapas = _etapasDisponiveis;
    if (etapas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma etapa disponível para anexo no momento.'),
        ),
      );
      return;
    }

    final etapa = etapas.length == 1 ? etapas.first : await _escolherEtapa(etapas);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            origem == 'camera'
                ? 'Não foi possível abrir a câmera.'
                : 'Não foi possível abrir o seletor de arquivos.',
          ),
        ),
      );
      return;
    }
    if (file == null || !mounted) return;

    // Validação no cliente (o service revalida): tipo e tamanho (15MB).
    final ext = file.path.split('.').last.toLowerCase();
    if (!_kAnexoExtensoes.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato inválido. Use PDF, JPG, PNG ou WEBP.'),
        ),
      );
      return;
    }
    if (await file.length() > 15 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arquivo acima do limite de 15MB.')),
      );
      return;
    }

    setState(() => _uploading = true);
    final res = await PurchaseProposalsService.instance.uploadAnexo(
      widget.proposalId,
      file,
      etapa: etapa,
      uploadedByName:
          ModuleAccessService.instance.userPermissions?.userName,
    );
    if (!mounted) return;
    setState(() => _uploading = false);

    if (res.success && res.data != null) {
      final approved = res.data!.status.toLowerCase() == 'approved';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Ficha anexada. Etapa ${_etapaLabel(etapa)} liberada.'
                : 'Ficha anexada. Aguardando aprovação do gestor.',
          ),
        ),
      );
      widget.onChanged?.call();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao anexar ficha.')),
      );
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
                title: Text('Etapa $e — ${_etapaLabel(e)}'),
                onTap: () => Navigator.of(ctx).pop(e),
              ),
            const SizedBox(height: 8),
          ],
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
              leading: Icon(Icons.photo_camera_rounded, color: _accent),
              title: const Text('Foto da câmera'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: Icon(Icons.upload_file_rounded, color: _accent),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anexo aprovado.')),
      );
      widget.onChanged?.call();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao aprovar anexo.')),
      );
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
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anexo rejeitado.')),
      );
      widget.onChanged?.call();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao rejeitar anexo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate =
        ModuleAccessService.instance.hasPermission('proposal:update');
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            children: [
              _SheetHeader(
                proposalNumber: widget.proposalNumber,
                etapa: _etapa,
                onClose: () => Navigator.of(ctx).pop(),
              ),
              TabBar(
                controller: _tab,
                indicatorColor: _accent,
                labelColor: _accent,
                unselectedLabelColor:
                    ThemeHelpers.textSecondaryColor(context),
                tabs: const [
                  Tab(text: 'Enviar / Status'),
                  Tab(text: 'Histórico'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _buildSendTab(scroll, canUpdate: canUpdate),
                    _buildHistoryTab(scroll),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSendTab(ScrollController scroll, {required bool canUpdate}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!),
        ),
      );
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _EtapaPicker(
          current: _etapa,
          accent: _accent,
          onChanged: (n) => setState(() => _etapa = n),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _abrirPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver PDF'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: const Text('Sincronizar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Status atual',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textSecondaryColor(context),
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 6),
        if (_signatures.isEmpty)
          Text(
            'Ainda não há assinaturas registradas para esta proposta.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
          )
        else
          ..._signatures.map(
            (s) => _SignatureTile(
              signature: s,
              accent: _accent,
              onCopyLink: () => _copiarLink(s),
              onOpenLink: () => _abrirLink(s),
              onResendEmail: canUpdate ? () => _reenviarEmail(s) : null,
              onResendWhatsapp:
                  canUpdate ? () => _reenviarWhatsapp(s) : null,
            ),
          ),
        if (canUpdate) ...[
          const SizedBox(height: 24),
          Text(
            'Enviar para assinatura (Etapa $_etapa)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          ..._forms.asMap().entries.map(
                (entry) => _SignerFormCard(
                  index: entry.key,
                  form: entry.value,
                  onRemove: _forms.length > 1
                      ? () => setState(() {
                            entry.value.dispose();
                            _forms.removeAt(entry.key);
                          })
                      : null,
                ),
              ),
          TextButton.icon(
            onPressed: () => setState(() => _forms.add(_SignerForm())),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar signatário'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _enviar,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.draw_rounded),
              label: const Text('Enviar para assinatura'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryTab(ScrollController scroll) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final h = _historico;
    if (h == null) {
      return const Center(child: Text('Histórico indisponível.'));
    }
    final events = [...h.stageHistory]..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)),
      );
    final atts = h.attachments;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          'Anexos físicos',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        if (atts.isEmpty)
          Text(
            'Sem anexos.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
          )
        else
          ...atts.map(
            (a) => _AttachmentTile(
              att: a,
              accent: _accent,
              onApprove: _isGestor && a.status.toLowerCase() == 'pending_approval'
                  ? () => _aprovarAnexo(a)
                  : null,
              onReject: _isGestor && a.status.toLowerCase() == 'pending_approval'
                  ? () => _rejeitarAnexo(a)
                  : null,
            ),
          ),
        if (_etapasDisponiveis.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _anexarFicha,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.note_add_outlined),
              label: const Text('Anexar ficha física'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Eventos',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text(
            'Sem eventos.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
          )
        else
          ...events.map((e) => _EventTile(event: e)),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.proposalNumber,
    required this.etapa,
    required this.onClose,
  });

  final String proposalNumber;
  final int etapa;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ASSINATURAS · ETAPA $etapa',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                ),
                Text(
                  'Proposta nº $proposalNumber',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _EtapaPicker extends StatelessWidget {
  const _EtapaPicker({
    required this.current,
    required this.accent,
    required this.onChanged,
  });

  final int current;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 3; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _EtapaChip(
                etapa: i,
                selected: current == i,
                accent: accent,
                onTap: () => onChanged(i),
              ),
            ),
          ),
      ],
    );
  }
}

class _EtapaChip extends StatelessWidget {
  const _EtapaChip({
    required this.etapa,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final int etapa;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (etapa) {
      1 => 'Comprador',
      2 => 'Proprietário',
      _ => 'Corretor',
    };
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.6)
                  : ThemeHelpers.borderColor(context),
            ),
          ),
          child: Column(
            children: [
              Text(
                'ETAPA $etapa',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? accent
                          : ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureTile extends StatelessWidget {
  const _SignatureTile({
    required this.signature,
    required this.accent,
    required this.onCopyLink,
    required this.onOpenLink,
    this.onResendEmail,
    this.onResendWhatsapp,
  });

  final ProposalSignature signature;
  final Color accent;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenLink;
  final VoidCallback? onResendEmail;
  final VoidCallback? onResendWhatsapp;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(signature.status);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  signature.statusLabel.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ETAPA ${signature.etapa}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Copiar link'),
                  ),
                  const PopupMenuItem(
                    value: 'open',
                    child: Text('Abrir link'),
                  ),
                  if (onResendEmail != null)
                    const PopupMenuItem(
                      value: 'email',
                      child: Text('Reenviar e-mail'),
                    ),
                  if (onResendWhatsapp != null)
                    const PopupMenuItem(
                      value: 'whatsapp',
                      child: Text('Reenviar WhatsApp'),
                    ),
                ],
                onSelected: (v) {
                  switch (v) {
                    case 'copy':
                      onCopyLink();
                      break;
                    case 'open':
                      onOpenLink();
                      break;
                    case 'email':
                      onResendEmail?.call();
                      break;
                    case 'whatsapp':
                      onResendWhatsapp?.call();
                      break;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            signature.signerName?.trim().isNotEmpty == true
                ? signature.signerName!
                : 'Signatário não identificado',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (signature.signerEmail != null)
            Text(
              signature.signerEmail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
            ),
          if (signature.signedAt != null)
            Text(
              'Assinada em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(signature.signedAt!.toLocal())}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
            ),
          if (signature.rejectionReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Motivo: ${signature.rejectionReason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFDC2626),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusTone(String s) {
    switch (s.toLowerCase()) {
      case 'signed':
        return const Color(0xFF16A34A);
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF6366F1);
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.att,
    required this.accent,
    this.onApprove,
    this.onReject,
  });

  final ProposalAttachment att;
  final Color accent;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = _statusTone(att.status);
    final etapaLabel = switch (att.etapa) {
      1 => 'Comprador',
      2 => 'Proprietário',
      _ => 'Corretor',
    };
    final canOpen = att.fileUrl.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(att.status).toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ETAPA ${att.etapa} · ${etapaLabel.toUpperCase()}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              if (canOpen)
                IconButton(
                  tooltip: 'Abrir',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  onPressed: () async {
                    final uri = Uri.tryParse(att.fileUrl);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  att.fileName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (att.uploadedByName != null && att.uploadedByName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Enviado por ${att.uploadedByName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: muted,
                    ),
              ),
            ),
          if (att.createdAt != null)
            Text(
              DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                  .format(att.createdAt!.toLocal()),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted,
                  ),
            ),
          if (att.rejectionReason != null &&
              att.rejectionReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Motivo: ${att.rejectionReason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFDC2626),
                    ),
              ),
            ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Rejeitar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0x55DC2626)),
                      ),
                    ),
                  ),
                if (onReject != null && onApprove != null)
                  const SizedBox(width: 10),
                if (onApprove != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Aprovar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
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

  Color _statusTone(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'pending_approval':
      case 'pending':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF6366F1);
    }
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado';
      case 'pending_approval':
      case 'pending':
        return 'Aguardando aprovação';
      default:
        return s;
    }
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final ProposalHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Text(
            'E${event.etapa}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.eventType,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (event.createdAt != null)
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(event.createdAt!.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

const List<String> _kAnexoExtensoes = ['pdf', 'jpg', 'jpeg', 'png', 'webp'];

class _SignerForm {
  _SignerForm()
      : name = TextEditingController(),
        email = TextEditingController(),
        phone = TextEditingController(),
        action = 'SIGN';

  _SignerForm.fromInput(ProposalSignerInput input)
      : name = TextEditingController(text: input.name),
        email = TextEditingController(text: input.email),
        phone = TextEditingController(text: input.phone ?? ''),
        action = input.action;

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  String action;

  bool get isValid =>
      name.text.trim().isNotEmpty && email.text.trim().contains('@');

  ProposalSignerInput toInput() => ProposalSignerInput(
        name: name.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
        action: action,
      );

  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
  }
}

class _SignerFormCard extends StatefulWidget {
  const _SignerFormCard({
    required this.index,
    required this.form,
    this.onRemove,
  });

  final int index;
  final _SignerForm form;
  final VoidCallback? onRemove;

  @override
  State<_SignerFormCard> createState() => _SignerFormCardState();
}

class _SignerFormCardState extends State<_SignerFormCard> {
  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Signatário ${widget.index + 1}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  tooltip: 'Remover',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          TextField(
            controller: f.name,
            decoration: const InputDecoration(
              labelText: 'Nome completo *',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: f.email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail *',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: f.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefone (WhatsApp)',
              helperText: 'Opcional — usado para reenviar link por WhatsApp',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: f.action,
            decoration: const InputDecoration(labelText: 'Ação'),
            items: const [
              DropdownMenuItem(value: 'SIGN', child: Text('Assinar')),
              DropdownMenuItem(value: 'APPROVE', child: Text('Aprovar')),
              DropdownMenuItem(value: 'RECOGNIZE', child: Text('Reconhecer')),
              DropdownMenuItem(
                value: 'SIGN_AS_A_WITNESS',
                child: Text('Assinar como testemunha'),
              ),
            ],
            onChanged: (v) => setState(() => f.action = v ?? 'SIGN'),
          ),
        ],
      ),
    );
  }
}
