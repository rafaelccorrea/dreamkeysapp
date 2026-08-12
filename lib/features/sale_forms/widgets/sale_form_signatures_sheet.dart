import 'dart:io' show File, Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';

/// Bottom sheet de assinaturas da FICHA DE VENDA.
///
/// Espelha o sheet de assinaturas da proposta, mas a ficha de venda é um fluxo
/// ÚNICO (sem etapas). Duas abas:
///  - **Enviar**: nome/mensagem do documento, prévia dos signatários
///    automáticos (obrigatórios da empresa + extraídos do PDF, read-only) e
///    lista editável de signatários extras.
///  - **Status**: resumo (total/assinados/pendentes), lista de assinaturas com
///    ações por item, sincronização, PDFs e (opcional) cancelamento em massa.
Future<void> showSaleFormSignaturesSheet(
  BuildContext context, {
  required String saleFormId,
  String? formNumber,
  bool canInvalidate = false,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _SaleFormSignaturesSheet(
      saleFormId: saleFormId,
      formNumber: formNumber,
      canInvalidate: canInvalidate,
      onChanged: onChanged,
    ),
  );
}

class _SaleFormSignaturesSheet extends StatefulWidget {
  const _SaleFormSignaturesSheet({
    required this.saleFormId,
    required this.formNumber,
    required this.canInvalidate,
    this.onChanged,
  });

  final String saleFormId;
  final String? formNumber;
  final bool canInvalidate;
  final VoidCallback? onChanged;

  @override
  State<_SaleFormSignaturesSheet> createState() =>
      _SaleFormSignaturesSheetState();
}

class _SaleFormSignaturesSheetState extends State<_SaleFormSignaturesSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  bool _sending = false;
  bool _syncing = false;
  bool _invalidating = false;

  List<SaleFormSignature> _signatures = const [];
  List<SaleFormSignerPreview> _autoSigners = const [];
  SaleFormWhatsappEnvio? _whatsapp;

  late final TextEditingController _docName;
  late final TextEditingController _docMessage;
  final List<_SignerForm> _forms = [_SignerForm()];

  Color get _green => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final num = widget.formNumber?.trim();
    _docName = TextEditingController(
      text: num == null || num.isEmpty
          ? 'Ficha de Venda'
          : 'Ficha de Venda $num',
    );
    _docMessage = TextEditingController();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sigsFut =
        SaleFormsService.instance.listSignatures(widget.saleFormId);
    final autoFut = SaleFormsService.instance
        .getAutomaticaSignersPreview(widget.saleFormId);
    final waFut = SaleFormsService.instance.getWhatsappEnvio(widget.saleFormId);
    final sigsRes = await sigsFut;
    final autoRes = await autoFut;
    final waRes = await waFut;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (sigsRes.success && sigsRes.data != null) {
        _signatures = sigsRes.data!;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = sigsRes.message;
        _errorStatus = sigsRes.statusCode;
      }
      if (autoRes.success && autoRes.data != null) {
        _autoSigners = autoRes.data!;
      }
      if (waRes.success && waRes.data != null) {
        _whatsapp = waRes.data;
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final res =
        await SaleFormsService.instance.syncAssinaturas(widget.saleFormId);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (res.success && res.data != null) {
      setState(() => _signatures = res.data!);
      _snack('Assinaturas sincronizadas.');
      widget.onChanged?.call();
    } else {
      _snack(res.message ?? 'Erro ao sincronizar.');
    }
  }

  Future<void> _enviar() async {
    final valid = _forms.where((f) => f.isValid).toList();
    setState(() => _sending = true);
    final res = await SaleFormsService.instance.enviarParaAssinatura(
      widget.saleFormId,
      signers: valid.map((f) => f.toInput()).toList(),
      documentName: _docName.text.trim().isEmpty ? null : _docName.text.trim(),
      documentMessage:
          _docMessage.text.trim().isEmpty ? null : _docMessage.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      _snack('Enviado para assinatura.');
      widget.onChanged?.call();
      _tab.animateTo(1);
      _load();
    } else {
      _snack(res.message ?? 'Erro ao enviar.');
    }
  }

  Future<void> _invalidar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar todas as assinaturas?'),
        content: const Text(
          'Todas as assinaturas em andamento serão canceladas e a ficha voltará '
          'a poder ser reenviada. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
            ),
            child: const Text('Cancelar todas'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _invalidating = true);
    final res =
        await SaleFormsService.instance.invalidarAssinaturas(widget.saleFormId);
    if (!mounted) return;
    setState(() => _invalidating = false);
    if (res.success) {
      _snack('Assinaturas canceladas. Você já pode reenviar.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao cancelar assinaturas.');
    }
  }

  Future<void> _abrirPdf(String modo) async {
    final res =
        await SaleFormsService.instance.downloadPdf(widget.saleFormId, modo: modo);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      _snack(res.message ?? 'Erro ao baixar PDF.');
      return;
    }
    try {
      final bytes = res.data!.bytes;
      final dir = Directory.systemTemp;
      final ext = res.data!.contentType.contains('zip') ? 'zip' : 'pdf';
      final num = widget.formNumber?.trim().isNotEmpty == true
          ? widget.formNumber!.trim()
          : widget.saleFormId;
      final file = File('${dir.path}/ficha_venda_${num}_$modo.$ext');
      await file.writeAsBytes(bytes);
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        _snack('PDF salvo em ${file.path}');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao abrir PDF: $e');
    }
  }

  /// Resolve o link de assinatura — usa `signatureUrl` se houver, senão busca.
  Future<String?> _resolveLink(SaleFormSignature sig) async {
    if (sig.signatureUrl != null && sig.signatureUrl!.trim().isNotEmpty) {
      return sig.signatureUrl!.trim();
    }
    final res = await SaleFormsService.instance
        .obterLinkAssinatura(widget.saleFormId, sig.id);
    if (res.success && res.data != null) return res.data;
    if (mounted) _snack(res.message ?? 'Erro ao obter link.');
    return null;
  }

  Future<void> _copiarLink(SaleFormSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _snack('Link copiado para a área de transferência.');
  }

  Future<void> _abrirLink(SaleFormSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    final uri = Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Compartilhamento manual via WhatsApp — abre o app com a mensagem pronta
  /// (usuário escolhe o contato). Sempre disponível.
  Future<void> _whatsappManual(SaleFormSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    final nome = sig.signerName?.trim();
    final saudacao = nome != null && nome.isNotEmpty ? 'Olá, $nome! ' : 'Olá! ';
    final texto =
        '${saudacao}Segue o link para assinatura da ficha de venda: $link';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Reenvio automático pelo backend (só quando a sessão permite).
  Future<void> _reenviarWhatsapp(SaleFormSignature sig) async {
    final res = await SaleFormsService.instance
        .reenviarUmWhatsapp(widget.saleFormId, sig.id);
    if (!mounted) return;
    _snack(res.success
        ? 'Reenvio via WhatsApp iniciado.'
        : res.message ?? 'Erro ao reenviar via WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate =
        ModuleAccessService.instance.hasPermission('sale_form:update');
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _SheetHeader(
                formNumber: widget.formNumber,
                onClose: () => Navigator.of(ctx).pop(),
              ),
              TabBar(
                controller: _tab,
                indicatorColor: _accent,
                labelColor: _accent,
                unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
                tabs: const [
                  Tab(text: 'Enviar'),
                  Tab(text: 'Status'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _buildSendTab(scroll, canUpdate: canUpdate),
                    _buildStatusTab(scroll),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Aba Enviar ────────────────────────────────────────────────────────────

  Widget _buildSendTab(ScrollController scroll, {required bool canUpdate}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!canUpdate) {
      return _LockedNotice(
        message:
            'Você não tem permissão para enviar esta ficha para assinatura.',
      );
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _SectionLabel('DOCUMENTO', accent: _accent),
        const SizedBox(height: 10),
        TextField(
          controller: _docName,
          decoration: const InputDecoration(
            labelText: 'Nome do documento',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _docMessage,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Mensagem (opcional)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 22),
        _SectionLabel('SIGNATÁRIOS AUTOMÁTICOS', accent: _accent),
        const SizedBox(height: 4),
        Text(
          'Incluídos automaticamente pelo sistema ao enviar — obrigatórios da '
          'empresa e signatários extraídos do documento.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.35,
              ),
        ),
        const SizedBox(height: 10),
        if (_autoSigners.isEmpty)
          _EmptyLine('Nenhum signatário automático identificado.')
        else
          ..._autoSigners.map((s) => _AutoSignerTile(signer: s)),
        const SizedBox(height: 22),
        _SectionLabel('SIGNATÁRIOS EXTRAS', accent: _accent),
        const SizedBox(height: 4),
        Text(
          'Opcional — adicione pessoas além dos automáticos.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _forms.add(_SignerForm())),
            icon: const Icon(Icons.add_rounded, size: 18),
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
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Aba Status ────────────────────────────────────────────────────────────

  Widget _buildStatusTab(ScrollController scroll) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _signatures.isEmpty) {
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.only(top: 12, bottom: 28),
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
    final total = _signatures.length;
    final assinados = _signatures.where((s) => s.isSigned).length;
    final rejeitados = _signatures.where((s) => s.isRejected).length;
    final pendentes = total - assinados - rejeitados;
    final hasSigned = assinados > 0;
    final canResendWa = _whatsapp?.canResend ?? false;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (total > 0) ...[
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Total',
                  value: '$total',
                  tone: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Assinados',
                  value: '$assinados',
                  tone: _green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Pendentes',
                  value: '$pendentes',
                  tone: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.status.warningDarkMode
                      : AppColors.status.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _abrirPdf('sistema'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF original'),
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
                    : const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Sincronizar'),
              ),
            ),
          ],
        ),
        if (hasSigned) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _abrirPdf('assinaturas'),
              icon: Icon(Icons.verified_outlined, size: 18, color: _green),
              label: Text(
                'Baixar documento assinado',
                style: TextStyle(color: _green),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _green.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel('ASSINATURAS', accent: _accent),
        const SizedBox(height: 10),
        if (_signatures.isEmpty)
          _EmptyState(
            icon: Icons.draw_outlined,
            title: 'Nenhuma assinatura ainda',
            subtitle:
                'Envie a ficha para assinatura na aba "Enviar" para acompanhar o status aqui.',
          )
        else
          ..._signatures.map(
            (s) => _SignatureTile(
              signature: s,
              onCopyLink: () => _copiarLink(s),
              onOpenLink: () => _abrirLink(s),
              onWhatsappManual: () => _whatsappManual(s),
              onResendWhatsapp: canResendWa ? () => _reenviarWhatsapp(s) : null,
            ),
          ),
        if (widget.canInvalidate && _signatures.isNotEmpty) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _invalidating ? null : _invalidar,
              icon: _invalidating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.cancel_outlined,
                      size: 18, color: AppColors.status.error),
              label: Text(
                'Cancelar todas para reenvio',
                style: TextStyle(color: AppColors.status.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppColors.status.error.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.formNumber, required this.onClose});
  final String? formNumber;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final num = formNumber?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSINATURAS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                    ),
                    Text(
                      num == null || num.isEmpty
                          ? 'Ficha de venda'
                          : 'Ficha de venda nº $num',
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
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                color: ThemeHelpers.textColor(context),
                fontSize: 11,
              ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context)
                .withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.tone});
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _AutoSignerTile extends StatelessWidget {
  const _AutoSignerTile({required this.signer});
  final SaleFormSignerPreview signer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMandatory = signer.source == 'mandatory';
    final tone = isMandatory
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.blueDarkMode : AppColors.status.blue);
    final badge = isMandatory
        ? 'EMPRESA'
        : signer.source == 'pdf'
            ? 'PDF'
            : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signer.name.trim().isEmpty
                      ? 'Signatário'
                      : signer.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (signer.email.trim().isNotEmpty)
                  Text(
                    signer.email,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                  ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      fontSize: 9.5,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SignatureTile extends StatelessWidget {
  const _SignatureTile({
    required this.signature,
    required this.onCopyLink,
    required this.onOpenLink,
    required this.onWhatsappManual,
    this.onResendWhatsapp,
  });

  final SaleFormSignature signature;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenLink;
  final VoidCallback onWhatsappManual;
  final VoidCallback? onResendWhatsapp;

  Color _tone(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (signature.isSigned) {
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    }
    if (signature.isRejected) {
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
    if (signature.status.toLowerCase() == 'viewed') {
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    }
    return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
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
                  signature.statusLabel.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
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
                  const PopupMenuItem(
                    value: 'wa',
                    child: Text('Compartilhar no WhatsApp'),
                  ),
                  if (onResendWhatsapp != null)
                    const PopupMenuItem(
                      value: 'resend',
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
                    case 'wa':
                      onWhatsappManual();
                      break;
                    case 'resend':
                      onResendWhatsapp?.call();
                      break;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    'Assinado em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(signature.signedAt!.toLocal())}',
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

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: muted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 30, color: muted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignerForm {
  _SignerForm()
      : name = TextEditingController(),
        email = TextEditingController();

  final TextEditingController name;
  final TextEditingController email;

  bool get isValid => name.text.trim().isNotEmpty;

  SaleFormSignerInput toInput() => SaleFormSignerInput(
        name: name.text.trim(),
        email: email.text.trim().isEmpty ? null : email.text.trim(),
      );

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

class _SignerFormCard extends StatelessWidget {
  const _SignerFormCard({
    required this.index,
    required this.form,
    this.onRemove,
  });

  final int index;
  final _SignerForm form;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
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
                'Signatário ${index + 1}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remover',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: form.name,
            decoration: const InputDecoration(
              labelText: 'Nome completo *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: form.email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
