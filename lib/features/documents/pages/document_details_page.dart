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
///
/// Leitura de cima para baixo: a capa diz o que é (tipo, formato, de quem);
/// logo abaixo, abrir e baixar; depois a "Situação" responde em que pé o
/// documento está e o que falta, com a ação no próprio item. Ação sem
/// permissão fica à vista, travada com cadeado e o motivo — nunca some.
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
  // Guardado junto da mensagem: sem o código HTTP, "sem permissão" e
  // "servidor fora do ar" viram a mesma frase no estado de erro.
  int _signaturesErrorStatus = 0;
  String? _busySignatureId;

  bool _acting = false;
  bool _downloading = false;

  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFmt = DateFormat('HH:mm');

  static const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  static const RoundedRectangleBorder _compactShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );

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
      _signaturesErrorStatus = 0;
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
        _signaturesErrorStatus = list.statusCode;
      }
      if (stats.success && stats.data != null) {
        _stats = stats.data;
      }
    });
  }

  /// Aviso no snackbar do tema (cartão com borda) — o significado vem do
  /// ícone colorido; fundo verde/vermelho com o texto escuro do tema perdia
  /// contraste, principalmente no modo escuro.
  void _snack(String text, {bool ok = false, bool locked = false}) {
    if (!mounted) return;
    final IconData icon;
    final Color tone;
    if (locked) {
      icon = Icons.lock_outline_rounded;
      tone = _lockTone(context);
    } else if (ok) {
      icon = Icons.check_circle_rounded;
      tone = _ok(context);
    } else {
      icon = Icons.error_outline_rounded;
      tone = _bad(context);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
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
        // Botão cheio sempre no tom escuro, que segura o texto branco nos
        // dois temas: vermelho só no destrutivo, verde na confirmação.
        // "Cancelar" é neutro (o tema pinta TextButton de vermelho).
        final confirmColor = destructive
            ? AppColors.status.error
            : AppColors.status.success;
        return AlertDialog(
          scrollable: true,
          icon: Icon(
            destructive
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            color: confirmColor,
            size: 28,
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
              ),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
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
          'Excluir "${_displayTitle(doc)}"? Esta ação não pode ser '
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
        // Editar fica à vista mesmo sem permissão: travado, com o motivo no
        // toque (regra do app — bloquear, não esconder).
        if (!locked && _document != null)
          IconButton(
            icon: canUpdate
                ? const Icon(Icons.edit_outlined)
                : _lockedIcon(context, Icons.edit_outlined),
            onPressed: canUpdate
                ? () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.documentEdit(_document!.id),
                    ).then((_) => _loadDocument());
                  }
                : () => _snack(
                      'Editar exige a permissão de alterar documentos. Peça '
                      'a um administrador da empresa.',
                      locked: true,
                    ),
            tooltip: canUpdate ? 'Editar' : 'Editar (sem permissão)',
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
                          reason: DocumentLockReason.unavailable,
                          title: 'Documento indisponível',
                          message:
                              'Não localizamos esse documento na biblioteca. '
                              'Ele pode ter sido removido ou você não tem '
                              'permissão para visualizá-lo.',
                          hint: 'Volte para a biblioteca e atualize a lista.',
                        )
                      : RefreshIndicator(
                          color: AppColors.primary.primary,
                          onRefresh: _loadDocument,
                          child: _buildContent(context, _document!),
                        ),
    );
  }

  /// Margem lateral: 16 no celular; em tablet a leitura fica numa coluna de
  /// até 720dp centrada (dado de ponta a ponta em 1000dp cansa o olho).
  double _sideInset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > 752 ? (width - 720) / 2 : 16.0;
  }

  /// Esqueleto fiel à página: capa, par de botões e duas seções com linhas.
  Widget _buildSkeleton() {
    final side = _sideInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 8, side, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 52, height: 64, borderRadius: 10),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 2),
                  FractionallySizedBox(
                    widthFactor: 0.9,
                    child: SkeletonText(height: 20),
                  ),
                  SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.55,
                    child: SkeletonText(height: 20),
                  ),
                  SizedBox(height: 10),
                  FractionallySizedBox(
                    widthFactor: 0.7,
                    child: SkeletonText(height: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
          ],
        ),
        for (final rows in const [3, 2]) ...[
          const SizedBox(height: 28),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.35,
            child: SkeletonText(height: 16),
          ),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.6,
            child: SkeletonText(height: 11),
          ),
          const SizedBox(height: 12),
          _hairline(context),
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) _divider(context),
            const _SkeletonRow(),
          ],
        ],
      ],
    );
  }

  Widget _buildContent(BuildContext context, Document doc) {
    final expiryDays = doc.expiryDate == null
        ? null
        : doc.expiryDate!.difference(DateTime.now()).inHours / 24;
    final isExpired = expiryDays != null && expiryDays < 0;
    final isExpiringSoon =
        expiryDays != null && expiryDays >= 0 && expiryDays <= 30;
    final hasDescription = (doc.description ?? '').trim().isNotEmpty;
    final hasNotes = (doc.notes ?? '').trim().isNotEmpty;
    final tags = (doc.tags ?? const <String>[])
        .where((t) => t.trim().isNotEmpty)
        .toList();
    final side = _sideInset(context);

    return ListView(
      // Fundo com folga: o botão flutuante do chat (bottom 80) não pode
      // cobrir a última linha quando a lista chega ao fim.
      padding: EdgeInsets.fromLTRB(
        side,
        8,
        side,
        96 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildHeader(context, doc),
        const SizedBox(height: 16),
        _buildFileActions(context, doc),
        _buildSituation(
          context,
          doc,
          expiryDays: expiryDays,
          isExpired: isExpired,
          isExpiringSoon: isExpiringSoon,
        ),
        _section(
          context,
          icon: Icons.draw_outlined,
          title: 'Assinaturas',
          meta: 'Quem já assinou, quem falta e o convite de cada um',
          children: [_buildSignatures(context)],
        ),
        _buildLinks(context, doc),
        if (hasDescription || hasNotes)
          _section(
            context,
            icon: Icons.notes_rounded,
            title: 'Descrição e observações',
            children: [
              if (hasDescription)
                _textBlock(context, 'Descrição', doc.description!.trim()),
              if (hasDescription && hasNotes) _divider(context),
              if (hasNotes)
                _textBlock(
                  context,
                  'Observações internas',
                  doc.notes!.trim(),
                ),
            ],
          ),
        if (tags.isNotEmpty)
          _section(
            context,
            icon: Icons.sell_outlined,
            title: 'Etiquetas',
            meta: _count(tags.length, 'etiqueta', 'etiquetas'),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in tags) _tagChip(context, t)],
                ),
              ),
            ],
          ),
        _section(
          context,
          icon: Icons.insert_drive_file_outlined,
          title: 'Arquivo',
          meta: 'Nome, formato, tamanho e validade',
          children: [
            _facts(
              context,
              _fileFacts(
                context,
                doc,
                expiryDays: expiryDays,
                isExpired: isExpired,
              ),
            ),
          ],
        ),
        _section(
          context,
          icon: Icons.history_rounded,
          title: 'Histórico',
          meta: 'Quem adicionou, quem revisou e a última alteração',
          children: _historyRows(context, doc),
        ),
        _buildDangerZone(context),
      ],
    );
  }

  // ─── Capa e ações do arquivo ──────────────────────────────────────────

  /// Capa: a folha com o formato do arquivo, o título e, numa linha só, o
  /// que evita um toque a mais — tipo, formato, tamanho e de quem é.
  Widget _buildHeader(BuildContext context, Document doc) {
    final theme = Theme.of(context);
    final ext = _extLabel(doc);
    final meta = <String>[
      doc.type.label,
      if (ext.isNotEmpty) ext,
      if (doc.fileSize > 0) _formatFileSize(doc.fileSize),
      if (doc.isEncrypted) 'criptografado',
    ].join(' · ');
    final clientName = doc.client?.name.trim() ?? '';
    final propertyTitle = doc.property?.title.trim() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FileSheet(label: ext, icon: _fileIcon(ext), tone: _brand(context)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayTitle(doc),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 21,
                  height: 1.22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (clientName.isNotEmpty)
                _headerLine(context, Icons.person_outline_rounded, clientName),
              if (propertyTitle.isNotEmpty)
                _headerLine(context, Icons.home_outlined, propertyTitle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerLine(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abrir e baixar — a ação que mais se faz aqui, logo abaixo da capa.
  Widget _buildFileActions(BuildContext context, Document doc) {
    final hasFile = doc.fileUrl.isNotEmpty;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final label = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: hasFile
                    ? () => DocumentFileActions.open(context, doc.fileUrl)
                    : null,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: _fitLabel('Visualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: _brand(context),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: _buttonShape,
                  textStyle: label,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: !hasFile || _downloading ? null : _download,
                icon: _downloading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: text,
                        ),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: _fitLabel(_downloading ? 'Baixando…' : 'Baixar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: text,
                  side: BorderSide(color: _outline(context)),
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: _buttonShape,
                  textStyle: label,
                ),
              ),
            ),
          ],
        ),
        if (!hasFile)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Este documento está sem arquivo anexado, então não há o '
                    'que abrir nem baixar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Situação: em que pé está e o que falta ───────────────────────────

  Widget _buildSituation(
    BuildContext context,
    Document doc, {
    required double? expiryDays,
    required bool isExpired,
    required bool isExpiringSoon,
  }) {
    final summary = _signatureSummary(doc);
    final signing = summary.total > 0 && summary.signed < summary.total;
    var attention = 0;
    if (doc.status == DocumentStatus.pendingReview ||
        doc.status == DocumentStatus.rejected) {
      attention++;
    }
    if (signing) attention++;
    if (isExpired || isExpiringSoon) attention++;

    final rows = <Widget>[
      _reviewRow(context, doc),
      _signatureRow(context, doc),
      if (doc.expiryDate != null && expiryDays != null)
        _expiryRow(
          context,
          doc.expiryDate!,
          expiryDays,
          isExpired: isExpired,
          isExpiringSoon: isExpiringSoon,
        ),
    ];

    // Enquanto as assinaturas não chegam, não dá para dizer "nada pendente".
    final checking =
        _loadingSignatures && _signatures.isEmpty && _stats == null;

    return _section(
      context,
      icon: Icons.fact_check_outlined,
      title: 'Situação',
      meta: checking
          ? 'Conferindo o andamento das assinaturas…'
          : attention == 0
              ? 'Nada pendente neste documento'
              : attention == 1
                  ? '1 ponto pede atenção'
                  : '$attention pontos pedem atenção',
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) _divider(context),
          rows[i],
        ],
      ],
    );
  }

  Widget _reviewRow(BuildContext context, Document doc) {
    final who = _byWhen(doc.approvedBy?.name, doc.approvedAt);
    switch (doc.status) {
      case DocumentStatus.pendingReview:
        return _stateRow(
          context,
          icon: Icons.hourglass_top_rounded,
          tone: _warn(context),
          title: 'Aguardando revisão',
          detail:
              'Precisa ser aprovado ou recusado por quem revisa documentos.',
          footer: DocumentPermissions.canApprove
              ? _reviewButtons(context)
              : _lockedNote(
                  context,
                  'Aprovar ou recusar',
                  'você não tem permissão para revisar documentos. Peça a '
                      'um administrador da empresa.',
                ),
        );
      case DocumentStatus.approved:
        return _stateRow(
          context,
          icon: Icons.verified_outlined,
          tone: _ok(context),
          title: 'Aprovado',
          detail: who ?? 'Revisado e liberado para uso.',
        );
      case DocumentStatus.rejected:
        return _stateRow(
          context,
          icon: Icons.block_rounded,
          tone: _bad(context),
          title: 'Rejeitado na revisão',
          detail: who ?? 'Quem revisou não aprovou este documento.',
        );
      case DocumentStatus.active:
        return _stateRow(
          context,
          icon: Icons.check_circle_outline_rounded,
          tone: _ok(context),
          title: 'Ativo na biblioteca',
          detail: 'Disponível para quem tem acesso aos documentos.',
        );
      case DocumentStatus.archived:
        return _stateRow(
          context,
          icon: Icons.inventory_2_outlined,
          tone: ThemeHelpers.textSecondaryColor(context),
          title: 'Arquivado',
          detail: 'Documento arquivado. Continua guardado na biblioteca.',
        );
      case DocumentStatus.deleted:
        return _stateRow(
          context,
          icon: Icons.delete_outline_rounded,
          tone: _bad(context),
          title: 'Excluído',
          detail: 'Este documento foi excluído da biblioteca.',
        );
    }
  }

  /// Resumo das assinaturas a partir do que chega de fato: estatísticas,
  /// senão a lista, senão o resumo do documento. (O `GET /documents/:id`
  /// não traz o resumo `signatures` — lido só dele, a Situação diria "sem
  /// assinaturas" com a lista cheia logo abaixo.)
  ({int total, int signed, int waiting, int rejected}) _signatureSummary(
    Document doc,
  ) {
    final st = _stats;
    if (st != null && st.total > 0) {
      return (
        total: st.total,
        signed: st.signed,
        waiting: st.pending + st.viewed,
        rejected: st.rejected,
      );
    }
    if (_signatures.isNotEmpty) {
      var signed = 0;
      var waiting = 0;
      var rejected = 0;
      for (final s in _signatures) {
        if (s.status == DocumentSignatureStatus.signed) {
          signed++;
        } else if (s.status.isSignable) {
          waiting++;
        } else if (s.status == DocumentSignatureStatus.rejected) {
          rejected++;
        }
      }
      return (
        total: _signatures.length,
        signed: signed,
        waiting: waiting,
        rejected: rejected,
      );
    }
    final sig = doc.signatures;
    if (sig != null && sig.hasSignatures && sig.total > 0) {
      return (
        total: sig.total,
        signed: sig.signed,
        waiting: sig.pending,
        rejected: sig.rejected,
      );
    }
    return (total: 0, signed: 0, waiting: 0, rejected: 0);
  }

  Widget _signatureRow(BuildContext context, Document doc) {
    // Regra do botão inalterada (igual ao web): "Enviar p/ assinatura" some
    // só com `allSigned` do documento; sem `document:create` fica travado,
    // com o motivo.
    final docAllSigned = doc.signatures?.allSigned ?? false;
    final Widget? footer = docAllSigned
        ? null
        : DocumentPermissions.canCreate
            ? _sendButton(context)
            : _lockedNote(
                context,
                'Enviar para assinatura',
                'você não tem permissão para enviar documentos. Peça a um '
                    'administrador da empresa.',
              );

    // Primeira carga das assinaturas: esqueleto no lugar de um "sem
    // assinaturas" que ainda não se sabe.
    if (_loadingSignatures && _signatures.isEmpty && _stats == null) {
      return const _SkeletonRow();
    }
    final s = _signatureSummary(doc);
    if (s.total == 0 && _signaturesError != null) {
      return _stateRow(
        context,
        icon: Icons.draw_outlined,
        tone: ThemeHelpers.textSecondaryColor(context),
        title: 'Assinaturas não conferidas',
        detail: 'Não foi possível carregar as assinaturas agora. O motivo '
            'aparece em Assinaturas, logo abaixo.',
        footer: footer,
      );
    }
    if (s.total == 0) {
      return _stateRow(
        context,
        icon: Icons.draw_outlined,
        tone: ThemeHelpers.textSecondaryColor(context),
        title: 'Sem assinaturas',
        detail: 'Ainda não foi enviado para ninguém assinar.',
        footer: footer,
      );
    }
    if (s.signed >= s.total) {
      return _stateRow(
        context,
        icon: Icons.task_alt_rounded,
        tone: _ok(context),
        title: 'Assinado por todos',
        detail: s.total == 1
            ? 'A assinatura pedida já foi concluída.'
            : 'As ${s.total} assinaturas pedidas foram concluídas.',
        footer: footer,
      );
    }

    // Quem falta, pelo nome, quando a lista já chegou; senão, a contagem.
    final names = _signatures
        .where((x) => x.status.isSignable)
        .map((x) => x.signerName.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    var detail = '';
    if (names.isNotEmpty) {
      final rest = names.length - 2;
      detail = 'Falta assinar: ${names.take(2).join(', ')}'
          '${rest > 0 ? ' e mais $rest' : ''}';
    } else if (s.waiting > 0) {
      detail = s.waiting == 1
          ? '1 assinatura aguardando.'
          : '${s.waiting} assinaturas aguardando.';
    } else {
      detail = 'Nenhuma assinatura aguardando no momento.';
    }
    if (s.rejected > 0) {
      detail += s.rejected == 1
          ? ' · 1 rejeitada'
          : ' · ${s.rejected} rejeitadas';
    }
    return _stateRow(
      context,
      icon: Icons.draw_outlined,
      tone: s.rejected > 0 && s.waiting == 0 ? _bad(context) : _warn(context),
      // O "X de Y" fica no medidor da seção Assinaturas; aqui, o que falta.
      title: 'Assinaturas em andamento',
      detail: detail,
      footer: footer,
    );
  }

  Widget _expiryRow(
    BuildContext context,
    DateTime expiry,
    double days, {
    required bool isExpired,
    required bool isExpiringSoon,
  }) {
    final date = _dateFmt.format(expiry.toLocal());
    final n = days.abs().ceil();
    if (isExpired) {
      return _stateRow(
        context,
        icon: Icons.event_busy_outlined,
        tone: _bad(context),
        title: 'Vencido',
        detail: 'Venceu em $date, há ${_count(n, 'dia', 'dias')}.',
      );
    }
    if (isExpiringSoon) {
      return _stateRow(
        context,
        icon: Icons.event_outlined,
        tone: _warn(context),
        title: n == 0 ? 'Vence hoje' : 'Vence em ${_count(n, 'dia', 'dias')}',
        detail: 'Validade até $date.',
      );
    }
    return _stateRow(
      context,
      icon: Icons.event_available_outlined,
      tone: _ok(context),
      title: 'Dentro da validade',
      detail: 'Válido até $date, faltam ${_count(n, 'dia', 'dias')}.',
    );
  }

  /// Linha flush da Situação: selo tonal, frase curta, detalhe e, quando
  /// cabe, a ação logo abaixo do texto (nunca à direita — em 320dp não há
  /// largura para texto e botão lado a lado).
  Widget _stateRow(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    String? detail,
    Widget? footer,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: _isDark(context) ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.4,
                    ),
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  footer,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Recusar (vermelho, contorno) e Aprovar (verde, cheio) dividindo a
  /// largura — rótulo encolhe em vez de cortar.
  Widget _reviewButtons(BuildContext context) {
    final bad = _bad(context);
    final label = _compactText(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _acting ? null : () => _review(DocumentStatus.rejected),
            icon: const Icon(Icons.close_rounded, size: 17),
            label: _fitLabel('Recusar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: bad,
              side: BorderSide(color: bad.withValues(alpha: 0.5)),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: _compactShape,
              textStyle: label,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed:
                _acting ? null : () => _review(DocumentStatus.approved),
            icon: const Icon(Icons.check_rounded, size: 17),
            label: _fitLabel('Aprovar'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.success,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: _compactShape,
              textStyle: label,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sendButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _acting ? null : _openSendForSignature,
      icon: const Icon(Icons.send_outlined, size: 17),
      label: _fitLabel('Enviar para assinatura'),
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        side: BorderSide(color: _outline(context)),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: _compactShape,
        textStyle: _compactText(context),
      ),
    );
  }

  /// Ação travada: cadeado violeta (família "permissão" do app) + qual ação
  /// e por quê — o usuário sabe que ela existe e quem libera.
  Widget _lockedNote(BuildContext context, String action, String reason) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: _lockTone(context),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$action: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: reason),
              ],
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }

  /// Ícone de ação travada: o próprio ícone apagado com um cadeado no canto.
  Widget _lockedIcon(BuildContext context, IconData icon) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: muted.withValues(alpha: 0.55)),
        Positioned(
          right: -5,
          bottom: -4,
          child: Icon(
            Icons.lock_rounded,
            size: 12,
            color: _lockTone(context),
          ),
        ),
      ],
    );
  }

  // ─── Assinaturas ──────────────────────────────────────────────────────

  Widget _buildSignatures(BuildContext context) {
    if (_loadingSignatures && _signatures.isEmpty) {
      return Column(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) _divider(context),
            const _SkeletonRow(),
          ],
        ],
      );
    }
    if (_signaturesError != null && _signatures.isEmpty) {
      return AppErrorState.fromApi(
        message: _signaturesError,
        statusCode: _signaturesErrorStatus,
        onRetry: _loadSignatures,
        dense: true,
      );
    }

    final stats = _stats;
    final hasMeter = stats != null && stats.total > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats != null && stats.total > 0) _signatureMeter(context, stats),
        if (_signatures.isEmpty)
          _emptyNote(
            context,
            icon: Icons.draw_outlined,
            title: 'Ninguém foi convidado a assinar ainda',
            text: 'Depois do envio para assinatura, cada signatário aparece '
                'aqui com o andamento (aguardando, visualizou, assinou), o '
                'link para assinar e o convite por e-mail.',
          )
        else
          for (var i = 0; i < _signatures.length; i++) ...[
            if (i > 0 || hasMeter) _divider(context),
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

  /// Número que importa em destaque (quantas já assinaram) + barra de
  /// composição por status + legenda só com o que existe (sem zeros).
  Widget _signatureMeter(BuildContext context, DocumentSignatureStats s) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final parts = <(int, Color, String)>[
      (s.signed, _ok(context), _count(s.signed, 'assinada', 'assinadas')),
      (
        s.viewed,
        _info(context),
        _count(s.viewed, 'visualizada', 'visualizadas'),
      ),
      (s.pending, _warn(context), '${s.pending} aguardando'),
      (
        s.rejected,
        _bad(context),
        _count(s.rejected, 'rejeitada', 'rejeitadas'),
      ),
      (s.expired, muted, _count(s.expired, 'expirada', 'expiradas')),
    ].where((p) => p.$1 > 0).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${s.signed}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.total == 1
                      ? 'de 1 assinatura concluída'
                      : 'de ${s.total} assinaturas concluídas',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                // stretch: sem ele cada faixa recebe altura solta e o
                // ColoredBox sem filho encolhe para 0 (barra invisível).
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < parts.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: parts[i].$1,
                        child: ColoredBox(color: parts[i].$2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final p in parts) _legend(context, p.$2, p.$3),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  // ─── Vínculos ─────────────────────────────────────────────────────────

  Widget _buildLinks(BuildContext context, Document doc) {
    final client = doc.client;
    final property = doc.property;
    return _section(
      context,
      icon: Icons.link_rounded,
      title: 'Vínculos',
      meta: 'Cliente e imóvel ligados a este documento',
      children: [
        if (client == null && property == null)
          _emptyNote(
            context,
            icon: Icons.link_off_rounded,
            title: 'Sem cliente ou imóvel vinculado',
            text: DocumentPermissions.canUpdate
                ? 'Para vincular, toque no lápis (Editar) no topo da tela.'
                : 'Quem pode editar documentos consegue fazer o vínculo.',
          ),
        if (client != null) _clientLink(context, client),
        if (client != null && property != null) _divider(context),
        if (property != null) _propertyLink(context, property),
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
    // Material transparente: sem ele o ripple é pintado por baixo do fundo
    // do shell e o toque não dá retorno visual.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: muted.withValues(
                    alpha: _isDark(context) ? 0.16 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.trim().isEmpty ? 'Sem nome' : name.trim(),
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
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 10),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: muted,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Arquivo e histórico ──────────────────────────────────────────────

  List<_Fact> _fileFacts(
    BuildContext context,
    Document doc, {
    required double? expiryDays,
    required bool isExpired,
  }) {
    String? expiry;
    if (doc.expiryDate != null && expiryDays != null) {
      final date = _dateFmt.format(doc.expiryDate!.toLocal());
      final n = expiryDays.abs().ceil();
      expiry = isExpired
          ? '$date · vencido há ${_count(n, 'dia', 'dias')}'
          : '$date · ${_count(n, 'dia restante', 'dias restantes')}';
    }
    return [
      _Fact('Nome original', doc.originalName, wide: true),
      _Fact('Formato', _extLabel(doc)),
      _Fact(
        'Tamanho',
        doc.fileSize > 0 ? _formatFileSize(doc.fileSize) : '',
      ),
      _Fact(
        'Criptografia',
        doc.isEncrypted ? 'Criptografado' : 'Não criptografado',
      ),
      if (expiry != null)
        _Fact(
          'Vencimento',
          expiry,
          color: isExpired ? _bad(context) : null,
        ),
      // Dados técnicos (paridade com o web): por último e sem destaque.
      _Fact('Nome no servidor', doc.fileName, wide: true),
      _Fact('Formato técnico (MIME)', doc.mimeType, wide: true),
    ];
  }

  /// Ficha em grade de 2 colunas com filetes (estilo dossiê); cai para 1
  /// coluna em tela estreita ou fonte muito grande. Altura sempre
  /// intrínseca: valor longo quebra linha em vez de estourar.
  Widget _facts(BuildContext context, List<_Fact> facts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final twoCols = constraints.maxWidth >= 300 && scale < 1.6;
        final rows = <List<_Fact>>[];
        _Fact? held;
        for (final f in facts) {
          if (!twoCols || f.wide) {
            if (held != null) {
              rows.add([held]);
              held = null;
            }
            rows.add([f]);
          } else if (held == null) {
            held = f;
          } else {
            rows.add([held, f]);
            held = null;
          }
        }
        if (held != null) rows.add([held]);
        final line = ThemeHelpers.borderColor(context).withValues(alpha: 0.6);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: line),
              if (rows[i].length == 1)
                _factCell(context, rows[i].first)
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _factCell(context, rows[i][0])),
                      Container(width: 1, color: line),
                      Expanded(
                        child: _factCell(context, rows[i][1], inset: true),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _factCell(BuildContext context, _Fact fact, {bool inset = false}) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final value = fact.value.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(inset ? 12 : 0, 11, 8, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fact.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? 'Não informado' : value,
            maxLines: fact.wide ? 4 : 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: value.isEmpty
                  ? muted
                  : fact.color ?? ThemeHelpers.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historyRows(BuildContext context, Document doc) {
    final uploader = doc.uploadedBy?.name.trim() ?? '';
    final reviewer = doc.approvedBy?.name.trim() ?? '';
    final reviewed = doc.approvedBy != null || doc.approvedAt != null;
    final rejected = doc.status == DocumentStatus.rejected;
    final String reviewTitle;
    if (rejected) {
      reviewTitle = reviewer.isEmpty
          ? 'Rejeitado na revisão'
          : 'Rejeitado por $reviewer';
    } else {
      reviewTitle =
          reviewer.isEmpty ? 'Aprovado na revisão' : 'Aprovado por $reviewer';
    }
    final rows = <Widget>[
      _historyRow(
        context,
        icon: Icons.upload_file_outlined,
        title: uploader.isEmpty
            ? 'Adicionado à biblioteca'
            : 'Adicionado por $uploader',
        when: _fullDate(doc.createdAt),
      ),
      if (reviewed)
        _historyRow(
          context,
          icon: rejected ? Icons.block_rounded : Icons.verified_outlined,
          tone: rejected ? _bad(context) : _ok(context),
          title: reviewTitle,
          when: doc.approvedAt != null
              ? _fullDate(doc.approvedAt!)
              : 'Data não registrada',
        ),
      _historyRow(
        context,
        icon: Icons.update_rounded,
        title: 'Última alteração',
        when: _fullDate(doc.updatedAt),
      ),
    ];
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) _divider(context),
        rows[i],
      ],
    ];
  }

  Widget _historyRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String when,
    Color? tone,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: tone ?? muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  when,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Exclusão no fim da página, separada do resto: ação sem volta não fica
  /// ao lado das ações do dia a dia.
  Widget _buildDangerZone(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final canDelete = DocumentPermissions.canDelete;
    final bad = _bad(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hairline(context),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: canDelete ? bad : muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Excluir documento',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Remove o documento da biblioteca. Não dá para '
                        'desfazer.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (canDelete)
                        OutlinedButton.icon(
                          onPressed: _acting ? null : _delete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                          ),
                          label: _fitLabel('Excluir'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: bad,
                            side: BorderSide(color: bad.withValues(alpha: 0.5)),
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: _compactShape,
                            textStyle: _compactText(context),
                          ),
                        )
                      else
                        _lockedNote(
                          context,
                          'Excluir',
                          'você não tem permissão para excluir documentos. '
                              'Peça a um administrador da empresa.',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Peças visuais ────────────────────────────────────────────────────

  /// Seção flush: ícone discreto + título forte + uma linha que diz o que
  /// tem ali; filete de largura total e o conteúdo encostado nas margens.
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
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _hairline(context),
          ...children,
        ],
      ),
    );
  }

  Widget _emptyNote(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String text,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: _isDark(context) ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textBlock(BuildContext context, String label, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(BuildContext context, String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sell_outlined,
            size: 13,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tag.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rótulo de botão que encolhe (em vez de cortar ou quebrar) quando a
  /// largura aperta — 320dp com fonte a 130%.
  Widget _fitLabel(String text) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }

  TextStyle? _compactText(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        );
  }

  Widget _hairline(BuildContext context) {
    return Container(height: 1, color: ThemeHelpers.borderColor(context));
  }

  Widget _divider(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
    );
  }

  // ─── Tons (sempre por token; variante *DarkMode no escuro) ─────────────

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _brand(BuildContext context) => _isDark(context)
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Color _ok(BuildContext context) => _isDark(context)
      ? AppColors.status.successDarkMode
      : AppColors.status.success;

  /// Âmbar: no claro usa o tom de texto de aviso — o âmbar de status some
  /// no branco (contraste ~1,7:1 contra ~3:1).
  Color _warn(BuildContext context) => _isDark(context)
      ? AppColors.status.warningDarkMode
      : AppColors.message.warningText;

  Color _bad(BuildContext context) => _isDark(context)
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  Color _info(BuildContext context) => _isDark(context)
      ? AppColors.status.infoDarkMode
      : AppColors.status.info;

  /// Violeta = permissão (mesma família do erro de permissão do app).
  Color _lockTone(BuildContext context) => _isDark(context)
      ? AppColors.status.purpleDarkMode
      : AppColors.status.purple;

  /// Contorno que aparece nos dois temas (no grafite a borda padrão some).
  Color _outline(BuildContext context) => _isDark(context)
      ? ThemeHelpers.borderLightColor(context)
      : ThemeHelpers.borderColor(context);

  // ─── Textos ───────────────────────────────────────────────────────────

  String _displayTitle(Document doc) {
    final title = doc.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final original = doc.originalName.trim();
    return original.isNotEmpty ? original : 'Documento sem nome';
  }

  /// Extensão para leitura: sem o ponto e em caixa alta ("PDF").
  String _extLabel(Document doc) {
    var ext = doc.fileExtension.trim();
    if (ext.startsWith('.')) ext = ext.substring(1);
    return ext.toUpperCase();
  }

  IconData _fileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
      case 'txt':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return Icons.image_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _count(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';

  String _fullDate(DateTime d) {
    final local = d.toLocal();
    return '${_dateFmt.format(local)} às ${_timeFmt.format(local)}';
  }

  /// "Por Maria Souza, em 12/09/2026 às 14:30" — com o que houver.
  String? _byWhen(String? name, DateTime? at) {
    final who = name?.trim() ?? '';
    if (who.isEmpty && at == null) return null;
    if (at == null) return 'Por $who';
    if (who.isEmpty) return 'Em ${_fullDate(at)}';
    return 'Por $who, em ${_fullDate(at)}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).toStringAsFixed(1);
      return '${kb.replaceAll('.', ',')} KB';
    }
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return '${mb.replaceAll('.', ',')} MB';
  }
}

/// Um dado da ficha do arquivo; [wide] ocupa a linha inteira (nomes longos).
class _Fact {
  final String label;
  final String value;
  final bool wide;
  final Color? color;

  const _Fact(this.label, this.value, {this.wide = false, this.color});
}

/// Linha de carregamento no formato das linhas reais (selo + duas linhas).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 36, height: 36, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.55,
                  child: SkeletonText(height: 14),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.85,
                  child: SkeletonText(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A "folha" da capa: página com a dobra no canto, o ícone do tipo de
/// arquivo e o formato escrito — identifica o documento antes do título.
class _FileSheet extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tone;

  const _FileSheet({
    required this.label,
    required this.icon,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 52,
      height: 64,
      child: CustomPaint(
        painter: _SheetPainter(
          fill: tone.withValues(alpha: dark ? 0.16 : 0.07),
          stroke: tone.withValues(alpha: dark ? 0.55 : 0.45),
          fold: tone.withValues(alpha: dark ? 0.32 : 0.2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 14, 5, 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 20, color: tone),
              if (label.isNotEmpty)
                // Flexible + FittedBox: com fonte grande o formato encolhe
                // dentro da folha em vez de vazar.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: tone,
                      ),
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

class _SheetPainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  final Color fold;

  const _SheetPainter({
    required this.fill,
    required this.stroke,
    required this.fold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 8.0;
    final w = size.width;
    final h = size.height;
    final f = w * 0.3;
    final body = Path()
      ..moveTo(r, 0)
      ..lineTo(w - f, 0)
      ..lineTo(w, f)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    final line = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(body, line);
    final corner = Path()
      ..moveTo(w - f, 0)
      ..lineTo(w - f, f - 3)
      ..quadraticBezierTo(w - f, f, w - f + 3, f)
      ..lineTo(w, f)
      ..close();
    canvas.drawPath(corner, Paint()..color = fold);
    canvas.drawPath(corner, line);
  }

  @override
  bool shouldRepaint(covariant _SheetPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke ||
      oldDelegate.fold != fold;
}
