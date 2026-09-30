import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';
import '../models/document_signature_model.dart';
import '../utils/document_file_actions.dart';
import '../utils/document_permissions.dart';
import '../widgets/document_access_locked.dart';
import '../widgets/document_signature_tile.dart';
import 'send_document_for_signature_page.dart';

/// Página de detalhes do documento — paridade com `DocumentDetailsPage.tsx`:
/// visualizar, baixar, editar, enviar para assinatura, excluir, vínculos
/// (cliente/imóvel), lista de assinaturas com envio/reenvio de e-mail e o
/// bloco de auditoria. Aprovar/recusar aparecem para documento pendente de
/// revisão com `document:approve`.
class DocumentDetailsPage extends StatefulWidget {
  final String documentId;

  const DocumentDetailsPage({
    super.key,
    required this.documentId,
  });

  @override
  State<DocumentDetailsPage> createState() => _DocumentDetailsPageState();
}

class _DocumentDetailsPageState extends State<DocumentDetailsPage> {
  final DocumentService _documentService = DocumentService.instance;
  Document? _document;
  bool _isLoading = true;
  String? _errorMessage;
  int _errorStatus = 0;

  List<DocumentSignature> _signatures = [];
  DocumentSignatureStats? _stats;
  bool _loadingSignatures = false;
  String? _signaturesError;
  String? _busySignatureId;

  bool _acting = false;
  bool _downloading = false;

  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    ModuleAccessService.instance.addListener(_onAccessChanged);
    _loadDocument();
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onAccessChanged);
    super.dispose();
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorStatus = 0;
    });

    final response = await _documentService.getDocumentById(widget.documentId);

    if (!mounted) return;
    if (response.success && response.data != null) {
      setState(() {
        _document = response.data;
        _isLoading = false;
      });
      _loadSignatures();
    } else {
      setState(() {
        _errorMessage = response.message ?? 'Erro ao carregar documento';
        _errorStatus = response.statusCode;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSignatures() async {
    setState(() {
      _loadingSignatures = true;
      _signaturesError = null;
    });
    // As duas chamadas partem juntas.
    final listFuture =
        _documentService.getDocumentSignatures(widget.documentId);
    final statsFuture =
        _documentService.getDocumentSignatureStats(widget.documentId);
    final list = await listFuture;
    final stats = await statsFuture;
    if (!mounted) return;
    setState(() {
      _loadingSignatures = false;
      if (list.success && list.data != null) {
        _signatures = list.data!;
      } else {
        _signaturesError = list.message ?? 'Erro ao carregar assinaturas';
      }
      if (stats.success && stats.data != null) {
        _stats = stats.data;
      }
    });
  }

  void _snack(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  // ─── Ações ────────────────────────────────────────────────────────────

  Future<void> _download() async {
    final doc = _document;
    if (doc == null || _downloading) return;
    setState(() => _downloading = true);
    await DocumentFileActions.download(
      context,
      doc.fileUrl,
      doc.originalName.isNotEmpty ? doc.originalName : doc.fileName,
    );
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _openSendForSignature() async {
    final doc = _document;
    if (doc == null) return;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SendDocumentForSignaturePage(documentId: doc.id),
      ),
    );
    if (sent == true && mounted) _loadDocument();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final confirmColor = destructive
            ? AppColors.status.error
            : AppColors.status.success;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(ctx),
              ),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: confirmColor),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _delete() async {
    final doc = _document;
    if (doc == null || _acting) return;
    final ok = await _confirm(
      title: 'Excluir documento',
      message:
          'Excluir "${doc.title ?? doc.originalName}"? Esta ação não pode ser '
          'desfeita.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    final res = await _documentService.deleteDocuments([doc.id]);
    if (!mounted) return;
    setState(() => _acting = false);
    if (res.success) {
      _snack('Documento excluído.', ok: true);
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Erro ao excluir documento.');
    }
  }

  Future<void> _review(DocumentStatus status) async {
    final doc = _document;
    if (doc == null || _acting) return;
    final approving = status == DocumentStatus.approved;
    final ok = await _confirm(
      title: approving ? 'Aprovar documento' : 'Recusar documento',
      message: approving
          ? 'Confirmar a aprovação deste documento?'
          : 'Confirmar a recusa deste documento?',
      confirmLabel: approving ? 'Aprovar' : 'Recusar',
      destructive: !approving,
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    final res = await _documentService.approveDocument(doc.id, status: status);
    if (!mounted) return;
    setState(() => _acting = false);
    if (res.success) {
      _snack(
        approving ? 'Documento aprovado.' : 'Documento rejeitado.',
        ok: true,
      );
      _loadDocument();
    } else {
      _snack(res.message ??
          (approving
              ? 'Erro ao aprovar documento.'
              : 'Erro ao rejeitar documento.'));
    }
  }

  Future<void> _sendEmail(DocumentSignature s, {required bool resend}) async {
    setState(() => _busySignatureId = s.id);
    final res = resend
        ? await _documentService.resendSignatureEmail(widget.documentId, s.id)
        : await _documentService.sendSignatureEmail(widget.documentId, s.id);
    if (!mounted) return;
    setState(() => _busySignatureId = null);
    if (res.success) {
      _snack(
        resend ? 'Email reenviado com sucesso!' : 'Email enviado com sucesso!',
        ok: true,
      );
      _loadSignatures();
    } else {
      _snack(res.message ??
          (resend ? 'Erro ao reenviar email' : 'Erro ao enviar email'));
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locked = !DocumentPermissions.canOpenLibrary;
    final canUpdate = DocumentPermissions.canUpdate;

    return AppScaffold(
      title: 'Documento',
      showBottomNavigation: false,
      actions: [
        if (!locked && _document != null && canUpdate)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.documentEdit(_document!.id),
              ).then((_) => _loadDocument());
            },
            tooltip: 'Editar',
          ),
      ],
      body: locked
          ? const DocumentAccessLocked()
          : _isLoading && _document == null
              ? _buildSkeleton()
              : _errorMessage != null
                  ? AppErrorState.fromApi(
                      message: _errorMessage,
                      statusCode: _errorStatus,
                      onRetry: _loadDocument,
                    )
                  : _document == null
                      ? const DocumentAccessLocked(
                          title: 'Documento indisponível',
                          message:
                              'Não localizamos esse documento na biblioteca. '
                              'Ele pode ter sido removido ou você não tem '
                              'permissão para visualizá-lo.',
                        )
                      : RefreshIndicator(
                          color: AppColors.primary.primary,
                          onRefresh: _loadDocument,
                          child: _buildContent(context, _document!),
                        ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        SkeletonBox(width: 140, height: 12, borderRadius: 6),
        SizedBox(height: 10),
        SkeletonBox(width: 260, height: 26, borderRadius: 8),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 28, borderRadius: 14),
        SizedBox(height: 20),
        SkeletonBox(width: double.infinity, height: 44, borderRadius: 12),
        SizedBox(height: 24),
        SkeletonBox(width: double.infinity, height: 180, borderRadius: 12),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 140, borderRadius: 12),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Document doc) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final sig = doc.signatures;
    final allSigned = sig?.allSigned ?? false;
    final expiryDays = doc.expiryDate == null
        ? null
        : doc.expiryDate!.difference(DateTime.now()).inHours / 24;
    final isExpired = expiryDays != null && expiryDays < 0;
    final isExpiringSoon =
        expiryDays != null && expiryDays >= 0 && expiryDays <= 30;

    final subtitleParts = <String>[];
    if (doc.title != null && doc.title != doc.originalName) {
      subtitleParts.add(doc.originalName);
    }
    if (doc.fileExtension.isNotEmpty) {
      subtitleParts.add(doc.fileExtension.toUpperCase());
    }
    if (doc.fileSize > 0) subtitleParts.add(_formatFileSize(doc.fileSize));

    final canCreate = DocumentPermissions.canCreate;
    final canDelete = DocumentPermissions.canDelete;
    final canApprove = DocumentPermissions.canApprove;
    final pendingReview = doc.status == DocumentStatus.pendingReview;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // ── Cabeçalho ────────────────────────────────────────────────
        Text(
          'DOCUMENTO · ${doc.type.label.toUpperCase()}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.primary.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          doc.title ?? doc.originalName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        if ((doc.description ?? '').isNotEmpty || subtitleParts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            (doc.description ?? '').isNotEmpty
                ? doc.description!
                : subtitleParts.join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(context, doc.status.label, _statusColor(doc.status)),
            _chip(context, doc.type.label, AppColors.primary.primary),
            if (doc.isEncrypted)
              _chip(context, 'Criptografado', AppColors.status.info),
            if (isExpired) _chip(context, 'Vencido', AppColors.status.error),
            if (!isExpired && isExpiringSoon)
              _chip(
                context,
                'Vence em ${expiryDays.ceil()}d',
                AppColors.status.warning,
              ),
            if (sig != null && sig.hasSignatures)
              _chip(
                context,
                '${sig.signed}/${sig.total} assinaturas',
                allSigned ? AppColors.status.success : AppColors.status.warning,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Ações ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: doc.fileUrl.isEmpty
                    ? null
                    : () => DocumentFileActions.open(context, doc.fileUrl),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text(
                  'Visualizar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: doc.fileUrl.isEmpty || _downloading
                    ? null
                    : _download,
                icon: _downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text(
                  'Baixar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  minimumSize: const Size(0, 46),
                ),
              ),
            ),
          ],
        ),
        if ((canCreate && !allSigned) ||
            (canApprove && pendingReview) ||
            canDelete) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canCreate && !allSigned)
                _secondaryAction(
                  context,
                  icon: Icons.send_outlined,
                  label: 'Enviar p/ assinatura',
                  onTap: _acting ? null : _openSendForSignature,
                ),
              if (canApprove && pendingReview) ...[
                _secondaryAction(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Aprovar',
                  color: AppColors.status.success,
                  onTap:
                      _acting ? null : () => _review(DocumentStatus.approved),
                ),
                _secondaryAction(
                  context,
                  icon: Icons.cancel_outlined,
                  label: 'Recusar',
                  color: AppColors.status.error,
                  onTap:
                      _acting ? null : () => _review(DocumentStatus.rejected),
                ),
              ],
              if (canDelete)
                _secondaryAction(
                  context,
                  icon: Icons.delete_outline_rounded,
                  label: 'Excluir',
                  color: AppColors.status.error,
                  onTap: _acting ? null : _delete,
                ),
            ],
          ),
        ],

        // ── Descrição & observações ─────────────────────────────────
        if ((doc.description ?? '').isNotEmpty || (doc.notes ?? '').isNotEmpty)
          _section(
            context,
            icon: Icons.info_outline_rounded,
            title: 'Descrição & observações',
            children: [
              if ((doc.description ?? '').isNotEmpty)
                _textBlock(context, 'Descrição', doc.description!),
              if ((doc.notes ?? '').isNotEmpty)
                _textBlock(context, 'Observações internas', doc.notes!),
            ],
          ),

        // ── Resumo do arquivo ────────────────────────────────────────
        _section(
          context,
          icon: Icons.insert_drive_file_outlined,
          title: 'Resumo do arquivo',
          children: [
            _infoRow(context, 'Status', doc.status.label),
            _infoRow(context, 'Tipo', doc.type.label),
            _infoRow(context, 'Nome original', doc.originalName),
            _infoRow(context, 'Nome do arquivo', doc.fileName),
            _infoRow(context, 'Tamanho', _formatFileSize(doc.fileSize)),
            _infoRow(
              context,
              'Extensão',
              doc.fileExtension.isEmpty ? '—' : doc.fileExtension.toUpperCase(),
            ),
            _infoRow(context, 'Tipo MIME', doc.mimeType),
            if (doc.expiryDate != null)
              _infoRow(
                context,
                'Vencimento',
                '${_dateFmt.format(doc.expiryDate!.toLocal())} · '
                    '${isExpired ? 'vencido há ${expiryDays.abs().ceil()} dia(s)' : '${(expiryDays ?? 0).ceil()} dia(s) restantes'}',
                valueColor: isExpired
                    ? AppColors.status.error
                    : (isExpiringSoon ? AppColors.status.warning : null),
              ),
          ],
        ),

        // ── Tags ─────────────────────────────────────────────────────
        if (doc.tags != null && doc.tags!.isNotEmpty)
          _section(
            context,
            icon: Icons.sell_outlined,
            title: 'Tags',
            meta:
                '${doc.tags!.length} ${doc.tags!.length == 1 ? 'etiqueta' : 'etiquetas'}',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in doc.tags!)
                      _chip(context, t, ThemeHelpers.textSecondaryColor(context)),
                  ],
                ),
              ),
            ],
          ),

        // ── Vínculos ─────────────────────────────────────────────────
        if (doc.client != null || doc.property != null)
          _section(
            context,
            icon: Icons.link_rounded,
            title: 'Vínculos',
            meta: 'A quem este documento se conecta',
            children: [
              if (doc.client != null) _clientLink(context, doc.client!),
              if (doc.property != null) _propertyLink(context, doc.property!),
            ],
          ),

        // ── Assinaturas ──────────────────────────────────────────────
        _section(
          context,
          icon: Icons.draw_outlined,
          title: 'Assinaturas',
          meta: _signaturesMeta(sig),
          children: [_buildSignatures(context)],
        ),

        // ── Segurança & auditoria ────────────────────────────────────
        _section(
          context,
          icon: Icons.shield_outlined,
          title: 'Segurança & auditoria',
          meta: 'Histórico de quem & quando',
          children: [
            _infoRow(
              context,
              'Enviado por',
              doc.uploadedBy?.name ?? '—',
            ),
            _infoRow(
              context,
              'Enviado em',
              _dateTimeFmt.format(doc.createdAt.toLocal()),
            ),
            _infoRow(
              context,
              'Atualizado em',
              _dateTimeFmt.format(doc.updatedAt.toLocal()),
            ),
            if (doc.approvedBy != null || doc.approvedAt != null)
              _infoRow(
                context,
                doc.status == DocumentStatus.rejected
                    ? 'Revisado por'
                    : 'Aprovado por',
                [
                  if (doc.approvedBy != null) doc.approvedBy!.name,
                  if (doc.approvedAt != null)
                    _dateTimeFmt.format(doc.approvedAt!.toLocal()),
                ].join(' · '),
              ),
            _infoRow(
              context,
              'Criptografia',
              doc.isEncrypted ? 'Ativa' : 'Não',
            ),
          ],
        ),
      ],
    );
  }

  String? _signaturesMeta(DocumentSignaturesInfo? sig) {
    if (sig == null || !sig.hasSignatures || sig.total == 0) return null;
    final pct = ((sig.signed / sig.total) * 100).round();
    final pend = sig.pending > 0
        ? ' · ${sig.pending} pendente${sig.pending > 1 ? 's' : ''}'
        : '';
    return '${sig.signed}/${sig.total} concluídas$pend · $pct%';
  }

  Widget _buildSignatures(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (_loadingSignatures && _signatures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SkeletonBox(width: double.infinity, height: 56, borderRadius: 10),
            SizedBox(height: 8),
            SkeletonBox(width: double.infinity, height: 56, borderRadius: 10),
          ],
        ),
      );
    }
    if (_signaturesError != null && _signatures.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _signaturesError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.status.error),
              ),
            ),
            TextButton(
              onPressed: _loadSignatures,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final stats = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats != null && stats.total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _stat(context, 'Total', stats.total, null),
                _stat(context, 'Pendentes', stats.pending,
                    DocumentSignatureStatus.pending),
                _stat(context, 'Visualizados', stats.viewed,
                    DocumentSignatureStatus.viewed),
                _stat(context, 'Assinados', stats.signed,
                    DocumentSignatureStatus.signed),
                _stat(context, 'Rejeitados', stats.rejected,
                    DocumentSignatureStatus.rejected),
                _stat(context, 'Expirados', stats.expired,
                    DocumentSignatureStatus.expired),
              ],
            ),
          ),
        if (_signatures.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Nenhuma assinatura. Envie este documento pelo botão '
              '"Enviar p/ assinatura".',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          for (var i = 0; i < _signatures.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
            _signatureTile(_signatures[i]),
          ],
      ],
    );
  }

  Widget _signatureTile(DocumentSignature s) {
    // Mesma regra do `DocumentSignatureCard` do web: "Enviar" para pendente;
    // "Reenviar" para visualizado, expirado ou pendente já visto.
    final canSend = s.status == DocumentSignatureStatus.pending;
    final canResend = s.status == DocumentSignatureStatus.viewed ||
        s.status == DocumentSignatureStatus.expired ||
        (s.status == DocumentSignatureStatus.pending && s.viewedAt != null);
    final url = s.signatureUrl;
    return DocumentSignatureTile(
      signature: s,
      busy: _busySignatureId == s.id,
      onOpenLink: (url != null && url.isNotEmpty && s.status.isSignable)
          ? () => DocumentFileActions.openSignatureLink(context, url)
          : null,
      onCopyLink: (url != null && url.isNotEmpty)
          ? () => DocumentFileActions.copyLink(
                context,
                url,
                message: 'Link de assinatura copiado',
              )
          : null,
      onSendEmail: canSend ? () => _sendEmail(s, resend: false) : null,
      onResendEmail: canResend ? () => _sendEmail(s, resend: true) : null,
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    int value,
    DocumentSignatureStatus? status,
  ) {
    final theme = Theme.of(context);
    final color = status == null
        ? ThemeHelpers.textColor(context)
        : signatureStatusColor(context, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  Widget _clientLink(BuildContext context, DocumentClient c) {
    final lines = <String>[
      if ((c.email ?? '').isNotEmpty) c.email!,
      if ((c.cpf ?? '').isNotEmpty) 'CPF ${Masks.cpf(c.cpf!)}',
      if ((c.phone ?? '').isNotEmpty) Masks.phone(c.phone!),
      if ((c.address ?? '').isNotEmpty)
        [
          c.address!,
          [c.city, c.state]
              .where((e) => e != null && e.isNotEmpty)
              .join('/'),
        ].where((e) => e.isNotEmpty).join(', '),
    ];
    return _linkTile(
      context,
      icon: Icons.person_outline_rounded,
      eyebrow: 'Cliente vinculado',
      name: c.name,
      lines: lines,
      onTap: c.id.isEmpty
          ? null
          : () => Navigator.pushNamed(context, AppRoutes.clientDetails(c.id)),
    );
  }

  Widget _propertyLink(BuildContext context, DocumentProperty p) {
    final lines = <String>[
      if ((p.code ?? '').isNotEmpty) 'Código ${p.code}',
      if ((p.address ?? '').isNotEmpty)
        [
          p.address!,
          [p.city, p.state]
              .where((e) => e != null && e.isNotEmpty)
              .join('/'),
        ].where((e) => e.isNotEmpty).join(', '),
    ];
    return _linkTile(
      context,
      icon: Icons.home_outlined,
      eyebrow: 'Imóvel vinculado',
      name: p.title,
      lines: lines,
      onTap: p.id.isEmpty
          ? null
          : () => Navigator.pushNamed(context, AppRoutes.propertyDetails(p.id)),
    );
  }

  Widget _linkTile(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String name,
    required List<String> lines,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.isEmpty ? '—' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Peças visuais ────────────────────────────────────────────────────

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? meta,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (meta != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor ?? ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textBlock(BuildContext context, String label, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    final fg = color ?? ThemeHelpers.textColor(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(
          color: color != null
              ? color.withValues(alpha: 0.45)
              : ThemeHelpers.borderColor(context),
        ),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Color _statusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.active:
      case DocumentStatus.approved:
        return AppColors.status.success;
      case DocumentStatus.pendingReview:
        return AppColors.status.warning;
      case DocumentStatus.rejected:
      case DocumentStatus.deleted:
        return AppColors.status.error;
      case DocumentStatus.archived:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
