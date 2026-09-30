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
///
/// Visual (revisão 30/09): o resumo responde de cara quantos obrigatórios
/// estão aprovados (régua de um traço por documento + legenda), o bloco
/// "próximo passo" traz a ação principal e cada documento é uma linha flush
/// com o arquivo tocável e as ações no próprio item — travadas com cadeado e
/// motivo quando falta cliente ou permissão. É uma `Column` de altura
/// natural, sem rolagem própria: monte dentro de uma lista rolável.
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
        // Fundo verde/vermelho: texto branco (a cor do tema sumia no escuro).
        content: Text(text, style: const TextStyle(color: Colors.white)),
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
      child = _buildSkeleton(context);
    } else if (_folder == null && _error != null) {
      child = _buildError(context);
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
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  // ─── Tons: sempre por token, na variante do tema ──────────────────────

  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  Color get _brandTone =>
      _dark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

  Color get _okTone =>
      _dark ? AppColors.status.successDarkMode : AppColors.status.success;

  /// No claro o âmbar de status (#E6B84C) quase some no branco: ícone e
  /// traço usam o âmbar de texto de mensagem, do mesmo sistema de cores.
  Color get _warnTone =>
      _dark ? AppColors.status.warningDarkMode : AppColors.message.warningText;

  Color get _badTone =>
      _dark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Color get _infoTone =>
      _dark ? AppColors.status.infoDarkMode : AppColors.status.info;

  /// Fundo neutro sólido dos botões secundários e do arquivo anexado.
  Color get _softFill => _dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundSecondary;

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final f = _folder;
    final String subtitle;
    if (_loading) {
      subtitle = 'Carregando os documentos do card…';
    } else if (f != null) {
      final parts = <String>[
        if ((f.empreendimento?.name ?? '').trim().isNotEmpty)
          f.empreendimento!.name.trim(),
        if ((f.kanbanTask?.client?.name ?? '').trim().isNotEmpty)
          f.kanbanTask!.client!.name.trim(),
      ];
      subtitle = parts.isEmpty
          ? 'Documentos exigidos nesta negociação'
          : parts.join(' · ');
    } else if (_error != null) {
      subtitle = 'Documentos exigidos nesta negociação';
    } else {
      subtitle = 'Ainda não iniciada neste card';
    }
    return Row(
      children: [
        _toneSquare(Icons.folder_open_rounded, _brandTone, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pasta de documentos',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Atualizar pasta',
          visualDensity: VisualDensity.compact,
          onPressed: _loading ? null : _load,
          icon: Icon(Icons.refresh_rounded, size: 20, color: muted),
        ),
      ],
    );
  }

  /// Esqueleto no desenho da pasta: resumo, régua, próximo passo e linhas.
  Widget _buildSkeleton(BuildContext context) {
    final line = Divider(
      height: 1,
      thickness: 1,
      color: ThemeHelpers.borderColor(context),
    );
    const row = Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 40, height: 40, borderRadius: 11),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 170, height: 14),
                    SizedBox(height: 8),
                    SkeletonText(width: 110, height: 11),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 42, borderRadius: 11)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 42, borderRadius: 11)),
            ],
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 92, height: 28, borderRadius: 6),
                  SizedBox(height: 6),
                  SkeletonText(width: 150, height: 12),
                ],
              ),
            ),
            SizedBox(width: 10),
            SkeletonBox(width: 104, height: 28, borderRadius: 9),
          ],
        ),
        const SizedBox(height: 14),
        const SkeletonBox(height: 8, borderRadius: 4),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            SkeletonText(width: 84, height: 12),
            SkeletonText(width: 90, height: 12),
            SkeletonText(width: 72, height: 12),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 72, borderRadius: 12),
        const SizedBox(height: 22),
        const SkeletonText(width: 160, height: 14),
        const SizedBox(height: 6),
        const SkeletonText(width: 200, height: 11),
        const SizedBox(height: 10),
        line,
        row,
        line,
        row,
      ],
    );
  }

  /// Falha ao carregar: a causa devolvida e "Tentar de novo". Sem o
  /// checklist embaixo — com erro não dá para saber se a pasta já existe.
  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final bad = _badTone;
    final cause = (_error ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: bad.withValues(alpha: _dark ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bad.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toneSquare(Icons.error_outline_rounded, bad, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Não foi possível abrir a pasta',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cause.isEmpty
                          ? 'O servidor não informou o motivo.'
                          : cause,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _actionButton(
            context,
            icon: Icons.refresh_rounded,
            label: 'Tentar de novo',
            onPressed: _load,
          ),
        ],
      ),
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
    final empName = (widget.empreendimentoName ?? '').trim();
    final templateOk = hasEmp && _templateReady == true;
    final checking = hasEmp && _checkingTemplate && !canStart;
    final pending = [hasClient, hasEmp, templateOk].where((ok) => !ok).length;

    String? templateHint;
    if (!hasEmp) {
      templateHint = 'Conferido assim que o empreendimento for identificado.';
    } else if (_checkingTemplate) {
      templateHint = 'Verificando o modelo de documentos do empreendimento…';
    } else if (_templateReady == false) {
      templateHint = 'Nenhum modelo de documentos ativo para '
          '${empName.isEmpty ? 'este empreendimento' : empName}. '
          'Configure o modelo em Empreendimentos antes de iniciar a pasta.';
    } else if (templateOk) {
      templateHint = 'Modelo ativo encontrado. Ao iniciar, os documentos '
          'exigidos aparecem aqui.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          pending == 0
              ? 'Tudo pronto para iniciar'
              : pending == 1
                  ? 'Falta 1 passo para iniciar a pasta'
                  : 'Faltam $pending passos para iniciar a pasta',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'A pasta reúne os documentos que o modelo do empreendimento '
          'exige. Você envia os arquivos ou manda um link para o $label '
          'enviar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        _step(
          context,
          number: 1,
          done: hasClient,
          active: step == 1,
          title: 'Vincular $label',
          hint: hasClient
              ? '${widget.clientLabel} vinculado ao card.'
              : 'Vincule o $label no card para liberar a pasta.',
        ),
        _step(
          context,
          number: 2,
          done: hasEmp,
          active: step == 2,
          title: 'Identificar empreendimento',
          hint: hasEmp
              ? (empName.isEmpty ? 'Empreendimento identificado.' : empName)
              : 'Vincule um imóvel com empreendimento ou selecione o '
                  'empreendimento no card.',
        ),
        _step(
          context,
          number: 3,
          done: templateOk,
          active: step == 3 && !templateOk,
          last: true,
          title: 'Modelo de documentos ativo',
          hint: templateHint,
          trailing: step == 3 && _templateReady == false && !_checkingTemplate
              ? _actionButton(
                  context,
                  icon: Icons.refresh_rounded,
                  label: 'Verificar de novo',
                  onPressed: _checkTemplate,
                )
              : null,
        ),
        const SizedBox(height: 18),
        _cta(
          context,
          icon: Icons.create_new_folder_outlined,
          label: checking ? 'Verificando o modelo…' : 'Iniciar pasta',
          fill: AppColors.primary.primary,
          busy: _creating || checking,
          locked: !canStart,
          onPressed: canStart && !_creating ? _createFolder : null,
        ),
        if (!canStart && !checking) ...[
          const SizedBox(height: 8),
          _lockNote(
            context,
            'O botão libera quando os três passos acima estiverem prontos.',
          ),
        ],
      ],
    );
  }

  /// Passo do checklist: selo numerado + texto. O fio entre os selos mostra
  /// a sequência e fica verde quando o passo de cima já está pronto.
  Widget _step(
    BuildContext context, {
    required int number,
    required bool done,
    required bool active,
    required String title,
    String? hint,
    Widget? trailing,
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final ok = _okTone;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final badge = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? ok : (active ? _brandTone : Colors.transparent),
        border: done || active
            ? null
            : Border.all(color: muted.withValues(alpha: 0.5), width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$number',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : muted,
                ),
              ),
            ),
    );
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(left: 42, bottom: last ? 0 : 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                    color: done || active
                        ? ThemeHelpers.textColor(context)
                        : muted,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 10),
                  trailing,
                ],
              ],
            ),
          ),
        ),
        Positioned(left: 0, top: 0, child: badge),
        if (!last)
          Positioned(
            left: 13,
            top: 32,
            bottom: 2,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: done
                    ? ok.withValues(alpha: 0.5)
                    : muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Com pasta ────────────────────────────────────────────────────────

  /// Leitura do web: completa = verde; incompleta e em revisão = âmbar;
  /// coletando = azul (andamento normal, nada enviado ainda); rascunho =
  /// neutro.
  Color _folderStatusColor(DocumentFolderStatus s) {
    switch (s) {
      case DocumentFolderStatus.complete:
        return _okTone;
      case DocumentFolderStatus.pendingReview:
      case DocumentFolderStatus.incomplete:
        return _warnTone;
      case DocumentFolderStatus.collecting:
        return _infoTone;
      case DocumentFolderStatus.draft:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _folderStatusIcon(DocumentFolderStatus s) {
    switch (s) {
      case DocumentFolderStatus.complete:
        return Icons.fact_check_outlined;
      case DocumentFolderStatus.pendingReview:
        return Icons.rate_review_outlined;
      case DocumentFolderStatus.incomplete:
        return Icons.incomplete_circle_rounded;
      case DocumentFolderStatus.collecting:
        return Icons.inventory_2_outlined;
      case DocumentFolderStatus.draft:
        return Icons.edit_note_rounded;
    }
  }

  Color _itemColor(DocumentFolderItemStatus s) {
    switch (s) {
      case DocumentFolderItemStatus.approved:
      case DocumentFolderItemStatus.uploaded:
        return _okTone;
      case DocumentFolderItemStatus.missing:
      case DocumentFolderItemStatus.rejected:
        return _badTone;
      case DocumentFolderItemStatus.pendingReview:
        return _warnTone;
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

  String? _itemHint(DocumentFolderItemStatus s, {required bool canReview}) {
    final label = widget.clientLabel.toLowerCase();
    switch (s) {
      case DocumentFolderItemStatus.missing:
        return 'Envie o arquivo ou gere um link para o $label enviar.';
      case DocumentFolderItemStatus.rejected:
        return 'Reenvie o arquivo corrigido ou peça um novo envio pelo link.';
      case DocumentFolderItemStatus.pendingReview:
        return canReview
            ? 'O $label enviou pelo link. Abra o arquivo e aprove ou '
                'rejeite.'
            : 'O $label enviou pelo link.';
      case DocumentFolderItemStatus.uploaded:
      case DocumentFolderItemStatus.approved:
        return null;
    }
  }

  Widget _buildFolder(BuildContext context, DocumentFolder f) {
    final items = f.items;
    final status = f.effectiveStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty) ...[
          _summary(context, f, status),
          const SizedBox(height: 16),
        ],
        _nextStep(context, f, status),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 22),
          _listHeader(context, f),
          const SizedBox(height: 10),
          for (final item in items) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: ThemeHelpers.borderColor(context),
            ),
            _itemRow(context, item),
          ],
        ],
      ],
    );
  }

  /// Resumo que responde de cara: quantos obrigatórios estão aprovados, o
  /// status da pasta, a régua (um traço por documento) e a legenda com o
  /// que falta. Sem obrigatórios, a conta passa a ser sobre todos os itens.
  Widget _summary(
    BuildContext context,
    DocumentFolder f,
    DocumentFolderStatus status,
  ) {
    final theme = Theme.of(context);
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasRequired = f.requiredCount > 0;
    final base =
        hasRequired ? f.items.where((i) => i.required).toList() : f.items;
    int count(DocumentFolderItemStatus s) =>
        base.where((i) => i.status == s).length;
    final done = base.where((i) => i.isDone).length;
    final review = count(DocumentFolderItemStatus.pendingReview);
    final rejected = count(DocumentFolderItemStatus.rejected);
    final missing = count(DocumentFolderItemStatus.missing);
    final caption = !hasRequired
        ? 'aprovados (nenhum documento é obrigatório)'
        : base.length == 1
            ? 'obrigatório aprovado'
            : 'obrigatórios aprovados';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$done',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: text,
                              height: 1.1,
                            ),
                          ),
                          TextSpan(
                            text: ' de ${base.length}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _statusStamp(context, status),
          ],
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(child: _meter(base)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            if (done > 0)
              _legend(
                context,
                Icons.check_circle_rounded,
                _okTone,
                done,
                done == 1 ? 'aprovado' : 'aprovados',
              ),
            if (review > 0)
              _legend(
                context,
                Icons.hourglass_top_rounded,
                _warnTone,
                review,
                'em revisão',
              ),
            if (rejected > 0)
              _legend(
                context,
                Icons.cancel_rounded,
                _badTone,
                rejected,
                rejected == 1 ? 'rejeitado' : 'rejeitados',
              ),
            if (missing > 0)
              _legend(
                context,
                Icons.upload_file_rounded,
                _badTone,
                missing,
                'faltando',
              ),
          ],
        ),
      ],
    );
  }

  /// Carimbo do status da pasta: ícone na cor do status, texto em tinta.
  Widget _statusStamp(BuildContext context, DocumentFolderStatus s) {
    final theme = Theme.of(context);
    final tone = _folderStatusColor(s);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: _dark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_folderStatusIcon(s), size: 15, color: tone),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                s.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Régua da pasta: um traço por documento, na ordem aprovado → em
  /// revisão → rejeitado → faltando, separados por 2px de folga. Acima de
  /// 40 documentos o traço ficaria fino demais e a régua soma por status.
  Widget _meter(List<DocumentFolderItem> base) {
    int rank(DocumentFolderItemStatus s) {
      switch (s) {
        case DocumentFolderItemStatus.approved:
        case DocumentFolderItemStatus.uploaded:
          return 0;
        case DocumentFolderItemStatus.pendingReview:
          return 1;
        case DocumentFolderItemStatus.rejected:
          return 2;
        case DocumentFolderItemStatus.missing:
          return 3;
      }
    }

    Color paint(int r) {
      switch (r) {
        case 0:
          return _okTone;
        case 1:
          return _warnTone;
        case 2:
          return _badTone;
        default:
          return _badTone.withValues(alpha: _dark ? 0.30 : 0.22);
      }
    }

    final ranks = base.map((i) => rank(i.status)).toList()..sort();
    // (status, peso) de cada traço.
    final segments = <MapEntry<int, int>>[];
    if (ranks.length <= 40) {
      for (final r in ranks) {
        segments.add(MapEntry(r, 1));
      }
    } else {
      for (var r = 0; r <= 3; r++) {
        final n = ranks.where((x) => x == r).length;
        if (n > 0) segments.add(MapEntry(r, n));
      }
    }
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++)
          Expanded(
            flex: segments[i].value,
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: paint(segments[i].key),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _legend(
    BuildContext context,
    IconData icon,
    Color tone,
    int count,
    String label,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tone),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$count ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                TextSpan(text: label),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// O que fazer agora, na ordem de prioridade da orientação do web
  /// (`getActiveFolderGuidance`). Pasta completa vem primeiro para o lote
  /// ZIP nunca sumir; pasta vazia vem antes de "sem cliente" para o
  /// "Aplicar modelo" continuar à mão como antes.
  Widget _nextStep(
    BuildContext context,
    DocumentFolder f,
    DocumentFolderStatus status,
  ) {
    final theme = Theme.of(context);
    final items = f.items;
    final label = widget.clientLabel.toLowerCase();
    final hasClient = (widget.clientId ?? '').isNotEmpty ||
        (f.kanbanTask?.clientId ?? '').isNotEmpty;
    final canReview = DocumentPermissions.canReviewFolderItems;
    final rejected = items
        .where((i) => i.status == DocumentFolderItemStatus.rejected)
        .length;
    final review = items
        .where((i) => i.status == DocumentFolderItemStatus.pendingReview)
        .length;
    final missing = items
        .where(
            (i) => i.required && i.status == DocumentFolderItemStatus.missing)
        .length;

    final IconData icon;
    final Color tone;
    final String title;
    final String body;
    Widget? cta;
    if (status == DocumentFolderStatus.complete) {
      icon = Icons.task_alt_rounded;
      tone = _okTone;
      title = 'Pasta completa';
      body = 'Todos os obrigatórios foram aprovados. Baixe o lote e envie '
          'para a incorporadora.';
      cta = _cta(
        context,
        icon: Icons.archive_outlined,
        label: _downloading ? 'Gerando ZIP…' : 'Baixar lote (ZIP)',
        fill: AppColors.status.success,
        busy: _downloading,
        onPressed: _downloading ? null : _downloadBundle,
      );
    } else if (items.isEmpty) {
      if (_templateReady == true) {
        icon = Icons.playlist_add_check_rounded;
        tone = _infoTone;
        title = 'Aplique o modelo de documentos';
        body = 'A pasta foi criada sem documentos. O modelo ativo do '
            'empreendimento lista os itens exigidos.';
        cta = _cta(
          context,
          icon: Icons.playlist_add_check_rounded,
          label: _syncing ? 'Aplicando…' : 'Aplicar modelo',
          fill: AppColors.primary.primary,
          busy: _syncing,
          onPressed: _syncing ? null : _syncTemplate,
        );
      } else if (_checkingTemplate) {
        icon = Icons.sync_rounded;
        tone = _infoTone;
        title = 'Verificando o modelo do empreendimento';
        body = 'Em instantes a pasta mostra se há documentos para aplicar.';
      } else {
        icon = Icons.settings_outlined;
        tone = _warnTone;
        title = 'Pasta sem documentos';
        body = 'O empreendimento não tem modelo de documentos ativo. '
            'Configure o modelo em Empreendimentos e toque em atualizar.';
      }
    } else if (!hasClient) {
      icon = Icons.person_add_alt_1_outlined;
      tone = _warnTone;
      title = 'Vincule o $label ao card';
      body = 'Sem $label vinculado não dá para enviar arquivos nem gerar '
          'links de envio.';
    } else if (rejected > 0) {
      icon = Icons.cancel_outlined;
      tone = _badTone;
      title = rejected == 1
          ? 'Reenvie 1 documento rejeitado'
          : 'Reenvie $rejected documentos rejeitados';
      body = 'Envie o arquivo corrigido ou gere um novo link para o $label.';
    } else if (review > 0) {
      icon = Icons.rate_review_outlined;
      tone = _warnTone;
      title = review == 1
          ? '1 envio do $label para revisar'
          : '$review envios do $label para revisar';
      body = canReview
          ? 'Abra o arquivo e aprove ou rejeite no próprio documento.'
          : 'A revisão fica com quem pode aprovar documentos.';
    } else if (missing > 0) {
      icon = Icons.upload_file_outlined;
      tone = _warnTone;
      title = missing == 1
          ? 'Falta 1 documento obrigatório'
          : 'Faltam $missing documentos obrigatórios';
      body = 'Envie o arquivo ou gere um link para o $label enviar.';
    } else {
      icon = Icons.info_outline_rounded;
      tone = _infoTone;
      title = 'Pasta em andamento';
      body = 'Use os botões de cada documento para enviar arquivos ou gerar '
          'links.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: _dark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toneSquare(icon, tone, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cta != null) ...[
            const SizedBox(height: 12),
            cta,
          ],
        ],
      ),
    );
  }

  Widget _listHeader(BuildContext context, DocumentFolder f) {
    final theme = Theme.of(context);
    final req = f.requiredCount;
    final opt = f.items.length - req;
    final anyFile = f.items.any((i) => (i.document?.fileUrl ?? '').isNotEmpty);
    final parts = <String>[
      if (req > 0) req == 1 ? '1 obrigatório' : '$req obrigatórios',
      if (opt > 0) opt == 1 ? '1 opcional' : '$opt opcionais',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Documentos da pasta',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          anyFile
              ? '${parts.join(' e ')} · toque no arquivo para abrir'
              : parts.join(' e '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  /// Linha flush de um documento: selo do status, nome, obrigatoriedade,
  /// orientação, o arquivo (toque abre, seta baixa) e as ações do item na
  /// largura toda. Sem cliente ou sem permissão, a ação aparece travada
  /// com cadeado e o motivo — nunca escondida.
  Widget _itemRow(BuildContext context, DocumentFolderItem item) {
    final theme = Theme.of(context);
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final color = _itemColor(item.status);
    final label = widget.clientLabel.toLowerCase();
    final hasClient = (widget.clientId ?? '').isNotEmpty ||
        (_folder?.kanbanTask?.clientId ?? '').isNotEmpty;
    final canReview = DocumentPermissions.canReviewFolderItems;
    final needsReview = item.status == DocumentFolderItemStatus.pendingReview;
    final doc = item.document;
    final fileUrl = doc?.fileUrl;
    final hasFile = fileUrl != null && fileUrl.isNotEmpty;
    final busy = _busyItemId == item.id;
    final showSend = item.status == DocumentFolderItemStatus.missing ||
        item.status == DocumentFolderItemStatus.rejected ||
        (needsReview && !canReview);
    final hint = _itemHint(item.status, canReview: canReview);
    final reason = item.status == DocumentFolderItemStatus.rejected
        ? (item.notes ?? '').trim()
        : '';

    Widget? actions;
    if (needsReview && canReview) {
      actions = _actionPair(
        _actionButton(
          context,
          icon: Icons.check_circle_outline_rounded,
          label: 'Aprovar',
          fill: AppColors.status.success,
          onPressed: busy ? null : () => _review(item, true),
        ),
        _actionButton(
          context,
          icon: Icons.cancel_outlined,
          label: 'Rejeitar',
          fill: AppColors.status.error,
          onPressed: busy ? null : () => _review(item, false),
        ),
      );
    } else if (showSend) {
      actions = _actionPair(
        _actionButton(
          context,
          icon: Icons.cloud_upload_outlined,
          label: 'Enviar arquivo',
          locked: !hasClient,
          onPressed: busy || !hasClient ? null : () => _upload(item),
        ),
        _actionButton(
          context,
          icon: Icons.link_rounded,
          label: 'Link p/ $label',
          locked: !hasClient,
          onPressed: busy || !hasClient ? null : () => _sendLink(item),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toneSquare(_itemIcon(item.status), color, busy: busy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: item.status.uiLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: text,
                            ),
                          ),
                          TextSpan(
                            text: item.required
                                ? '  ·  Obrigatório'
                                : '  ·  Opcional',
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Motivo da recusa: $reason',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: text,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (doc != null && (hasFile || doc.originalName.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _fileSlab(context, item, doc, fileUrl: fileUrl, hasFile: hasFile),
          ],
          if (showSend && !hasClient) ...[
            const SizedBox(height: 10),
            _lockNote(
              context,
              'Vincule o $label ao card para enviar o arquivo ou gerar o '
              'link.',
            ),
          ],
          if (needsReview && !canReview) ...[
            const SizedBox(height: 10),
            _lockNote(
              context,
              'Aprovar ou rejeitar exige a permissão de aprovar documentos.',
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: 12),
            actions,
          ],
        ],
      ),
    );
  }

  /// O arquivo do item como peça tocável: tipo, nome, "toque para abrir" e
  /// o botão de baixar. Sem endereço, mostra o nome e avisa que não abre.
  Widget _fileSlab(
    BuildContext context,
    DocumentFolderItem item,
    DocumentFolderItemDocument doc, {
    required String? fileUrl,
    required bool hasFile,
  }) {
    final theme = Theme.of(context);
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final (kindIcon, kindLabel) = _fileKind(doc);
    final name = doc.originalName.isNotEmpty ? doc.originalName : item.label;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasFile
                ? () => DocumentFileActions.open(context, fileUrl)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: _softFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeHelpers.borderColor(context)),
              ),
              child: Row(
                children: [
                  Icon(kindIcon, size: 22, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: text,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasFile
                              ? '$kindLabel · toque para abrir'
                              : '$kindLabel · arquivo indisponível',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasFile)
                    IconButton(
                      tooltip: 'Baixar arquivo',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => DocumentFileActions.download(
                        context,
                        fileUrl,
                        name,
                      ),
                      icon: Icon(Icons.download_rounded, size: 20, color: text),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ícone e rótulo do tipo do arquivo, pelo mime ou pela extensão.
  (IconData, String) _fileKind(DocumentFolderItemDocument doc) {
    final mime = (doc.mimeType ?? '').toLowerCase();
    final name = doc.originalName.toLowerCase();
    final dot = name.lastIndexOf('.');
    final raw = dot >= 0 ? name.substring(dot + 1) : '';
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(raw) ? raw : '';
    final up = ext.toUpperCase();
    if (mime.contains('pdf') || ext == 'pdf') {
      return (Icons.picture_as_pdf_outlined, 'PDF');
    }
    if (mime.startsWith('image/') ||
        const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'].contains(ext)) {
      return (Icons.image_outlined, ext.isEmpty ? 'Imagem' : 'Imagem $up');
    }
    if (mime.contains('word') || ext == 'doc' || ext == 'docx') {
      return (Icons.description_outlined, 'Documento Word');
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        const ['xls', 'xlsx', 'csv'].contains(ext)) {
      return (Icons.table_chart_outlined, 'Planilha');
    }
    if (mime.contains('zip') || ext == 'zip' || ext == 'rar') {
      return (Icons.folder_zip_outlined, 'Arquivo compactado');
    }
    return (
      Icons.insert_drive_file_outlined,
      ext.isEmpty ? 'Arquivo' : 'Arquivo $up',
    );
  }

  // ─── Peças ────────────────────────────────────────────────────────────

  /// Quadrado tonal com ícone (ou carregando) — a marca de cor fica aqui,
  /// o texto ao lado segue em tinta de texto.
  Widget _toneSquare(
    IconData icon,
    Color tone, {
    double size = 40,
    bool busy = false,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: _dark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: busy
          ? SizedBox(
              width: size * 0.45,
              height: size * 0.45,
              child: CircularProgressIndicator(strokeWidth: 2, color: tone),
            )
          : Icon(icon, size: size * 0.5, color: tone),
    );
  }

  Widget _lockNote(BuildContext context, String text) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_outline_rounded, size: 15, color: muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// Ação principal em largura cheia (teto de 440 em tela larga). Travada:
  /// fundo neutro + cadeado; ocupada: mantém a cor e mostra o progresso.
  Widget _cta(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color fill,
    required VoidCallback? onPressed,
    bool busy = false,
    bool locked = false,
  }) {
    final theme = Theme.of(context);
    final bg = locked ? _softFill : fill;
    final fg = locked ? ThemeHelpers.textSecondaryColor(context) : Colors.white;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Icon(locked ? Icons.lock_outline_rounded : icon, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, softWrap: false),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              disabledBackgroundColor: bg,
              disabledForegroundColor: fg,
              elevation: 0,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              side: locked
                  ? BorderSide(color: ThemeHelpers.borderColor(context))
                  : BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Duas ações do item lado a lado, metade cada (teto de 560 em tela
  /// larga). Quando a metade não comporta o rótulo na escala de texto do
  /// aparelho (tela estreita + fonte grande), um fica embaixo do outro na
  /// largura toda; no limite, o rótulo encolhe dentro do botão.
  Widget _actionPair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 560 ? constraints.maxWidth : 560.0;
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        if ((width - 8) / 2 < 128 * scale) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [first, const SizedBox(height: 8), second],
              ),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: 8),
                Expanded(child: second),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Botão de ação do item. Sem [fill] é neutro (fundo sólido + filete);
  /// com [fill] é cheio com texto branco (verde confirma, vermelho recusa).
  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? fill,
    bool locked = false,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(locked ? Icons.lock_outline_rounded : icon, size: 17),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: fill ?? _softFill,
        foregroundColor:
            fill != null ? Colors.white : ThemeHelpers.textColor(context),
        disabledBackgroundColor: _softFill,
        disabledForegroundColor: muted.withValues(alpha: 0.75),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: fill != null
            ? BorderSide.none
            : BorderSide(color: ThemeHelpers.borderColor(context)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
