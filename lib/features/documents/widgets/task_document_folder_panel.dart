import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/document_folder_model.dart';
import '../services/document_folder_service.dart';
import '../utils/document_file_actions.dart';
import '../utils/document_permissions.dart';

/// Pasta de documentos do card do CRM — paridade com
/// `TaskDocumentFolderPanel.tsx` do web.
///
/// Sem pasta: checklist de 3 passos (cliente vinculado, empreendimento
/// identificado, modelo ativo) e "Iniciar pasta". Com pasta: status,
/// progresso dos obrigatórios, itens com enviar arquivo, gerar link para o
/// cliente, visualizar/baixar, aprovar/rejeitar o que chegou pelo link e o
/// lote ZIP quando completa.
///
/// Vincular cliente, imóvel e empreendimento continua sendo feito no próprio
/// card; o painel recebe o estado atual por parâmetro.
class TaskDocumentFolderPanel extends StatefulWidget {
  final String taskId;
  final String? clientId;
  final String? empreendimentoId;
  final String? empreendimentoName;

  /// "Cliente" (venda) ou "Locatário" etc. — o web recebe `clientLabel`.
  final String clientLabel;

  const TaskDocumentFolderPanel({
    super.key,
    required this.taskId,
    this.clientId,
    this.empreendimentoId,
    this.empreendimentoName,
    this.clientLabel = 'Cliente',
  });

  @override
  State<TaskDocumentFolderPanel> createState() =>
      _TaskDocumentFolderPanelState();
}

class _TaskDocumentFolderPanelState extends State<TaskDocumentFolderPanel> {
  final DocumentFolderService _service = DocumentFolderService.instance;

  DocumentFolder? _folder;
  bool _loading = true;
  String? _error;

  bool? _templateReady;
  bool _checkingTemplate = false;

  bool _creating = false;
  bool _syncing = false;
  bool _downloading = false;
  String? _busyItemId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskDocumentFolderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _load();
    } else if (oldWidget.empreendimentoId != widget.empreendimentoId) {
      _checkTemplate();
    }
  }

  String? get _empreendimentoIdForTemplate =>
      _folder?.empreendimentoId ?? widget.empreendimentoId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _service.getByTask(widget.taskId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success) {
        _folder = r.data;
      } else {
        _folder = null;
        _error = r.message;
      }
    });
    _checkTemplate();
  }

  Future<void> _checkTemplate() async {
    final empId = _empreendimentoIdForTemplate;
    if (empId == null || empId.isEmpty) {
      if (mounted) setState(() => _templateReady = null);
      return;
    }
    setState(() => _checkingTemplate = true);
    final r = await _service.hasActiveTemplate(empId);
    if (!mounted) return;
    setState(() {
      _checkingTemplate = false;
      _templateReady = r.success ? (r.data ?? false) : false;
    });
  }

  void _snack(String text, {bool ok = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  // ─── Ações ────────────────────────────────────────────────────────────

  Future<void> _createFolder() async {
    setState(() => _creating = true);
    final r = await _service.createFromTask(widget.taskId);
    if (!mounted) return;
    setState(() => _creating = false);
    if (r.success && r.data != null) {
      setState(() => _folder = r.data);
      _snack('Pasta de documentos iniciada', ok: true);
    } else {
      _snack(r.message ?? 'Erro ao criar pasta');
    }
  }

  Future<void> _syncTemplate() async {
    final f = _folder;
    if (f == null) return;
    setState(() => _syncing = true);
    final r = await _service.syncFromTemplate(f.id);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (r.success && r.data != null) {
      setState(() => _folder = r.data);
      _snack('Modelo de documentos aplicado à pasta', ok: true);
      _checkTemplate();
    } else {
      _snack(r.message ?? 'Erro ao aplicar modelo');
    }
  }

  Future<void> _upload(DocumentFolderItem item) async {
    final f = _folder;
    if (f == null) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _busyItemId = item.id);
    final r = await _service.uploadItem(f.id, item.id, File(path));
    if (!mounted) return;
    setState(() => _busyItemId = null);
    if (r.success && r.data != null) {
      setState(() => _folder = r.data);
      _snack('Documento enviado e aprovado', ok: true);
    } else {
      _snack(r.message ?? 'Erro no upload');
    }
  }

  Future<void> _sendLink(DocumentFolderItem item) async {
    final f = _folder;
    if (f == null) return;
    setState(() => _busyItemId = item.id);
    final r = await _service.sendItemLink(f.id, item.id);
    if (!mounted) return;
    setState(() => _busyItemId = null);
    final url = r.data;
    if (r.success && url != null) {
      await Clipboard.setData(ClipboardData(text: url));
      _snack(
        'Link copiado para a área de transferência',
        ok: true,
        action: SnackBarAction(
          label: 'Compartilhar',
          textColor: Colors.white,
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: '${item.label}: $url'),
          ),
        ),
      );
    } else {
      _snack(r.message ?? 'Erro ao gerar link');
    }
  }

  Future<void> _review(DocumentFolderItem item, bool approve) async {
    final f = _folder;
    if (f == null) return;
    setState(() => _busyItemId = item.id);
    final r = await _service.reviewItem(f.id, item.id, approve: approve);
    if (!mounted) return;
    setState(() => _busyItemId = null);
    if (r.success && r.data != null) {
      setState(() => _folder = r.data);
      _snack(
        approve
            ? 'Documento aprovado'
            : 'Documento rejeitado — solicite reenvio ao cliente',
        ok: true,
      );
    } else {
      _snack(r.message ?? 'Erro ao revisar documento');
    }
  }

  Future<void> _downloadBundle() async {
    final f = _folder;
    if (f == null) return;
    setState(() => _downloading = true);
    final r = await _service.downloadBundle(f.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      try {
        final path =
            await DocumentFileActions.saveBytes(r.data!.value, r.data!.key);
        await DocumentFileActions.shareFile(path, subject: r.data!.key);
        _snack('Lote baixado com sucesso', ok: true);
      } catch (e) {
        _snack('Erro ao baixar lote: $e');
      }
    } else {
      _snack(r.message ?? 'Erro ao baixar lote');
    }
    if (mounted) setState(() => _downloading = false);
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_loading) {
      child = const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(width: double.infinity, height: 20, borderRadius: 6),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 64, borderRadius: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 64, borderRadius: 12),
        ],
      );
    } else if (_folder == null) {
      child = _buildSetup(context);
    } else {
      child = _buildFolder(context, _folder!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.folder_open_rounded,
            size: 18, color: AppColors.primary.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Pasta de documentos',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Atualizar',
          visualDensity: VisualDensity.compact,
          onPressed: _loading ? null : _load,
          icon: Icon(
            Icons.refresh_rounded,
            size: 20,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  // ─── Sem pasta: checklist para iniciar ────────────────────────────────

  Widget _buildSetup(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasClient = (widget.clientId ?? '').isNotEmpty;
    final hasEmp = (widget.empreendimentoId ?? '').isNotEmpty;
    final canStart = hasClient && hasEmp && _templateReady == true;
    final step = !hasClient ? 1 : (!hasEmp ? 2 : 3);
    final label = widget.clientLabel.toLowerCase();

    String? templateHint;
    if (hasClient && hasEmp) {
      if (_checkingTemplate) {
        templateHint = 'Verificando o modelo de documentos do empreendimento…';
      } else if (_templateReady == false) {
        templateHint = 'Nenhum modelo de documentos ativo para '
            '${widget.empreendimentoName ?? 'este empreendimento'}. '
            'Configure o modelo em Empreendimentos antes de iniciar a pasta.';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.status.error),
            ),
          ),
        Text(
          'Checklist para iniciar',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        _step(
          context,
          number: 1,
          done: hasClient,
          active: step == 1,
          title: 'Vincular $label',
          hint: hasClient
              ? 'Concluído.'
              : 'Vincule o $label no card para liberar a pasta.',
        ),
        _step(
          context,
          number: 2,
          done: hasEmp,
          active: step == 2,
          title: 'Identificar empreendimento',
          hint: hasEmp
              ? (widget.empreendimentoName ?? 'Concluído.')
              : 'Vincule um imóvel com empreendimento ou selecione o '
                  'empreendimento no card.',
        ),
        _step(
          context,
          number: 3,
          done: canStart,
          active: step == 3,
          title: 'Iniciar pasta',
          hint: templateHint ??
              (step == 3 ? null : 'Conclua os passos anteriores.'),
          trailing: step == 3
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canStart)
                      FilledButton.icon(
                        onPressed: _creating ? null : _createFolder,
                        icon: _creating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.create_new_folder_outlined,
                                size: 18),
                        label: const Text('Iniciar pasta'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (_templateReady == false && !_checkingTemplate)
                      OutlinedButton.icon(
                        onPressed: _checkTemplate,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Verificar de novo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeHelpers.textColor(context),
                          side: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                      ),
                  ],
                )
              : null,
        ),
        if (!hasClient || !hasEmp)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A pasta reúne os documentos exigidos pelo modelo do '
              'empreendimento, com envio por link para o $label.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }

  Widget _step(
    BuildContext context, {
    required int number,
    required bool done,
    required bool active,
    required String title,
    String? hint,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final ok = AppColors.status.success;
    final primary = AppColors.primary.primary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final badgeColor = done ? ok : (active ? primary : muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done || active
                  ? badgeColor
                  : badgeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Text(
                    '$number',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : muted,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 8),
                  trailing,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Com pasta ────────────────────────────────────────────────────────

  Color _folderStatusColor(DocumentFolderStatus s) {
    switch (s) {
      case DocumentFolderStatus.complete:
        return AppColors.status.success;
      case DocumentFolderStatus.pendingReview:
        return AppColors.status.warning;
      case DocumentFolderStatus.incomplete:
      case DocumentFolderStatus.collecting:
        return AppColors.status.error;
      case DocumentFolderStatus.draft:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  Color _itemColor(DocumentFolderItemStatus s) {
    switch (s) {
      case DocumentFolderItemStatus.approved:
      case DocumentFolderItemStatus.uploaded:
        return AppColors.status.success;
      case DocumentFolderItemStatus.missing:
      case DocumentFolderItemStatus.rejected:
        return AppColors.status.error;
      case DocumentFolderItemStatus.pendingReview:
        return AppColors.status.warning;
    }
  }

  IconData _itemIcon(DocumentFolderItemStatus s) {
    switch (s) {
      case DocumentFolderItemStatus.approved:
      case DocumentFolderItemStatus.uploaded:
        return Icons.check_circle_outline_rounded;
      case DocumentFolderItemStatus.missing:
        return Icons.upload_file_outlined;
      case DocumentFolderItemStatus.rejected:
        return Icons.cancel_outlined;
      case DocumentFolderItemStatus.pendingReview:
        return Icons.hourglass_top_rounded;
    }
  }

  String? _itemHint(DocumentFolderItemStatus s) {
    switch (s) {
      case DocumentFolderItemStatus.missing:
        return 'Envie o arquivo ou gere um link para o cliente.';
      case DocumentFolderItemStatus.rejected:
        return 'Reenvie o documento corrigido ou peça novo envio via link.';
      case DocumentFolderItemStatus.pendingReview:
        return 'Enviado pelo cliente via link — aprove ou rejeite.';
      case DocumentFolderItemStatus.uploaded:
      case DocumentFolderItemStatus.approved:
        return null;
    }
  }

  Widget _buildFolder(BuildContext context, DocumentFolder f) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final status = f.effectiveStatus;
    final complete = status == DocumentFolderStatus.complete;
    final statusColor = _folderStatusColor(status);
    final items = f.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _pill(context, status.label, statusColor),
            if (f.empreendimento != null)
              _pill(context, f.empreendimento!.name, muted),
            if (!complete)
              Text(
                items.isEmpty
                    ? 'Nenhum documento na pasta'
                    : '${f.approvedRequiredCount}/${f.requiredCount} '
                        'obrigatórios aprovados',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (items.isNotEmpty && !complete) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: f.progressPct / 100,
              minHeight: 6,
              color: AppColors.primary.primary,
              backgroundColor: ThemeHelpers.borderColor(context),
            ),
          ),
        ],
        if (complete) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _downloading ? null : _downloadBundle,
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.archive_outlined, size: 18),
            label: Text(_downloading ? 'Gerando ZIP…' : 'Baixar lote (ZIP)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
        if (items.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _templateReady == true
                ? 'A pasta foi criada sem documentos. Aplique o modelo ativo '
                    'do empreendimento para listar os itens exigidos.'
                : 'A pasta está sem documentos e o empreendimento não tem '
                    'modelo ativo. Configure o modelo em Empreendimentos.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (_templateReady == true) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncTemplate,
              icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
              label: Text(_syncing ? 'Aplicando…' : 'Aplicar modelo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary.primary,
                side: BorderSide(
                  color: AppColors.primary.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          _itemRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _itemRow(BuildContext context, DocumentFolderItem item) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final color = _itemColor(item.status);
    final hint = _itemHint(item.status);
    final hasClient = (widget.clientId ?? '').isNotEmpty ||
        (_folder?.kanbanTask?.clientId ?? '').isNotEmpty;
    final canReview = DocumentPermissions.canReviewFolderItems;
    final needsReview = item.status == DocumentFolderItemStatus.pendingReview;
    final fileUrl = item.document?.fileUrl;
    final hasFile = fileUrl != null && fileUrl.isNotEmpty;
    final busy = _busyItemId == item.id;
    final showSend = item.status == DocumentFolderItemStatus.missing ||
        item.status == DocumentFolderItemStatus.rejected ||
        (needsReview && !canReview);

    final actions = <Widget>[
      if (hasFile) ...[
        _miniAction(
          context,
          Icons.visibility_outlined,
          'Visualizar',
          () => DocumentFileActions.open(context, fileUrl),
        ),
        _miniAction(
          context,
          Icons.download_outlined,
          'Baixar',
          () => DocumentFileActions.download(
            context,
            fileUrl,
            item.document!.originalName.isNotEmpty
                ? item.document!.originalName
                : item.label,
          ),
        ),
      ],
      if (needsReview && canReview) ...[
        _miniAction(
          context,
          Icons.check_circle_outline_rounded,
          'Aprovar',
          busy ? null : () => _review(item, true),
          color: AppColors.status.success,
        ),
        _miniAction(
          context,
          Icons.cancel_outlined,
          'Rejeitar',
          busy ? null : () => _review(item, false),
          color: AppColors.status.error,
        ),
      ],
      if (showSend) ...[
        _miniAction(
          context,
          Icons.cloud_upload_outlined,
          'Enviar',
          busy || !hasClient ? null : () => _upload(item),
        ),
        _miniAction(
          context,
          Icons.link_rounded,
          'Link cliente',
          busy || !hasClient ? null : () => _sendLink(item),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_itemIcon(item.status), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.required ? '${item.label} *' : item.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _pill(context, item.status.uiLabel, color),
                  ],
                ),
                if ((item.document?.originalName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: hasFile
                        ? () => DocumentFileActions.open(context, fileUrl)
                        : null,
                    child: Text(
                      item.document!.originalName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hasFile ? AppColors.primary.primary : muted,
                        decoration:
                            hasFile ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (showSend && !hasClient) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Vincule um cliente ao card primeiro.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.status.warning),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? color,
  }) {
    final fg = onTap == null
        ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.5)
        : (color ?? ThemeHelpers.textColor(context));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color != null && onTap != null
                  ? color.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String label, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
