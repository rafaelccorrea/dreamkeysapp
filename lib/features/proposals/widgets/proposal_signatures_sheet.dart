import 'dart:io' show File, Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          ...atts.map((a) => _AttachmentTile(att: a)),
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
  const _AttachmentTile({required this.att});
  final ProposalAttachment att;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.attach_file_rounded),
      title: Text(
        att.fileName,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Etapa ${att.etapa} • ${att.status}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
      ),
      onTap: () async {
        if (att.fileUrl.isEmpty) return;
        final uri = Uri.tryParse(att.fileUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
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
