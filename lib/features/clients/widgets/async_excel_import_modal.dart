import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../services/client_service.dart';
import '../utils/client_spreadsheet.dart';

/// Modal para importação assíncrona de clientes via Excel.
///
/// O caminho é mostrado como passos numerados, na ordem em que a pessoa
/// age: (1) baixar o modelo, se quiser; (2) escolher a planilha; (3) enviar
/// e acompanhar o processamento; (4) baixar a planilha de erros, quando
/// alguma linha for recusada.
class AsyncExcelImportModal extends StatefulWidget {
  final Function()? onImportComplete;

  const AsyncExcelImportModal({super.key, this.onImportComplete});

  @override
  State<AsyncExcelImportModal> createState() => _AsyncExcelImportModalState();
}

class _AsyncExcelImportModalState extends State<AsyncExcelImportModal> {
  File? _selectedFile;
  String? _jobId;
  bool _isUploading = false;
  bool _isPolling = false;
  String? _errorMessage;

  String? _status;
  int? _totalRows;
  int? _processedRows;
  int? _successCount;
  int? _errorCount;
  double? _progress;
  bool _hasErrorFile = false;
  bool _downloadingErrors = false;
  bool _autoDownloadedErrors = false;

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _successTone(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
  }

  Color _errorTone(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
  }

  String? _fileName(File? file) {
    if (file == null) return null;
    return file.path.split(Platform.pathSeparator).last;
  }

  String _bytesPretty(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  /// Enquanto envia/processa, o modal não fecha (nem pelo X nem pelo rodapé).
  bool get _locked => (_isUploading || _isPolling) && _status != 'completed';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final mq = MediaQuery.of(context);

    // Teto de 88% da tela + corpo rolável: cabe em paisagem e em tela baixa;
    // o recuo do teclado entra por baixo.
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              _buildHeader(context, accent, theme),
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderLightColor(context),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: _jobId == null
                      ? _buildSelectionStage(context, accent)
                      : _buildProcessingStage(context, accent, theme),
                ),
              ),
              _buildFooter(context, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    final String subtitle;
    if (_jobId == null) {
      subtitle = 'Traga vários clientes de uma vez por planilha.';
    } else if (_status == 'completed') {
      subtitle = 'Importação finalizada.';
    } else if (_status == 'failed') {
      subtitle = 'A importação não foi concluída.';
    } else {
      subtitle = 'Acompanhe o processamento aqui mesmo.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withValues(alpha: isDark ? 0.16 : 0.09),
              border: Border.all(color: accent.withValues(alpha: 0.26)),
            ),
            child: Icon(Icons.upload_file_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importar clientes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: muted,
            disabledColor: muted.withValues(alpha: 0.35),
            tooltip: 'Fechar',
            onPressed: _locked ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Antes de enviar ─────────────────────────

  Widget _buildSelectionStage(BuildContext context, Color accent) {
    final hasFile = _selectedFile != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ImportStep(
          number: 1,
          title: 'Baixe o modelo',
          tag: 'opcional',
          subtitle: 'Colunas esperadas, uma linha de instruções e exemplos '
              'de preenchimento. Preencha no Excel ou no Google Planilhas.',
          state: _StepState.todo,
          child: Row(
            children: [
              Expanded(
                child: _buildTemplateButton(
                  context,
                  icon: Icons.table_chart_outlined,
                  label: 'Modelo Excel',
                  onTap: () => _downloadTemplate(csv: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTemplateButton(
                  context,
                  icon: Icons.description_outlined,
                  label: 'Modelo CSV',
                  onTap: () => _downloadTemplate(csv: true),
                ),
              ),
            ],
          ),
        ),
        _ImportStep(
          number: 2,
          title: 'Escolha a planilha',
          subtitle: 'Arquivo .xlsx, .xls ou .csv, com o cabeçalho na '
              'primeira linha.',
          state: hasFile ? _StepState.done : _StepState.active,
          child: _buildFilePicker(context, accent),
        ),
        const _ImportStep(
          number: 3,
          title: 'Envie e acompanhe',
          subtitle: 'As linhas são lidas em segundo plano e o andamento '
              'aparece aqui. As que tiverem erro voltam numa planilha, com '
              'o motivo de cada uma, para você corrigir e enviar de novo.',
          state: _StepState.todo,
          last: true,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(context, _errorMessage!),
        ],
      ],
    );
  }

  Widget _buildTemplateButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: _isUploading ? null : onTap,
      icon: Icon(icon, size: 18, color: _accentColor(context)),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  /// Área de escolha do arquivo: tracejada enquanto vazia; com o arquivo,
  /// mostra nome, tamanho e o atalho para trocar.
  Widget _buildFilePicker(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fileName = _fileName(_selectedFile);
    final hasFile = fileName != null;
    final tone = hasFile ? _successTone(context) : accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isUploading ? null : _selectFile,
        borderRadius: BorderRadius.circular(14),
        child: DottedBorder(
          color: hasFile ? tone : ThemeHelpers.borderColor(context),
          radius: 14,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hasFile
                  ? tone.withValues(alpha: isDark ? 0.10 : 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
                  ),
                  child: Icon(
                    hasFile
                        ? Icons.insert_drive_file_outlined
                        : Icons.cloud_upload_outlined,
                    size: 22,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName ?? 'Toque para escolher o arquivo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (hasFile)
                        FutureBuilder<int>(
                          future: _selectedFile?.length(),
                          builder: (context, snapshot) {
                            final size = snapshot.data;
                            return Text(
                              size == null
                                  ? 'Toque para trocar'
                                  : '${_bytesPretty(size)} · toque para trocar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        )
                      else
                        Text(
                          'Do celular, do Drive ou de onde ele estiver salvo.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  hasFile ? Icons.swap_horiz_rounded : Icons.chevron_right_rounded,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    final tone = _errorTone(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: tone, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Depois de enviar ─────────────────────────

  Widget _buildProcessingStage(
    BuildContext context,
    Color accent,
    ThemeData theme,
  ) {
    final completed = _status == 'completed';
    final failed = _status == 'failed';
    final errors = _errorCount ?? 0;
    final showErrorFile = completed && errors > 0 && _hasErrorFile;
    final fileName = _fileName(_selectedFile);

    final String stepTitle;
    final String? stepSubtitle;
    if (completed) {
      stepTitle = 'Importação concluída';
      stepSubtitle = errors > 0
          ? (_hasErrorFile
              ? 'Parte das linhas foi recusada — veja o passo abaixo.'
              : 'Parte das linhas foi recusada.')
          : 'Todas as linhas lidas foram importadas.';
    } else if (failed) {
      stepTitle = 'A importação falhou';
      stepSubtitle = null;
    } else {
      stepTitle = 'Lendo as linhas';
      stepSubtitle = 'Pode levar alguns minutos — acompanhe aqui até terminar.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ImportStep(
          number: 1,
          title: 'Planilha enviada',
          subtitle: fileName,
          state: _StepState.done,
        ),
        _ImportStep(
          number: 2,
          title: stepTitle,
          subtitle: stepSubtitle,
          state: completed
              ? _StepState.done
              : (failed ? _StepState.error : _StepState.active),
          last: !showErrorFile,
          child: _buildProgressPanel(context, accent, completed, failed),
        ),
        if (showErrorFile)
          _ImportStep(
            number: 3,
            title: 'Corrija as linhas com erro',
            subtitle: 'A planilha de erros traz cada linha recusada e o '
                'motivo. Corrija e importe de novo.',
            state: _StepState.active,
            last: true,
            child: OutlinedButton.icon(
              onPressed: _downloadingErrors ? null : _downloadErrorFile,
              icon: _downloadingErrors
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _errorTone(context),
                      ),
                    )
                  : Icon(
                      Icons.download_rounded,
                      size: 18,
                      color: _errorTone(context),
                    ),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _downloadingErrors
                      ? 'Baixando…'
                      : 'Baixar planilha de erros',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(
                  color: _errorTone(context).withValues(alpha: 0.45),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        if (failed) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(
            context,
            _errorMessage ?? 'Não foi possível concluir a importação.',
          ),
        ],
      ],
    );
  }

  /// Percentual em destaque, barra de progresso e a contagem do resultado.
  Widget _buildProgressPanel(
    BuildContext context,
    Color accent,
    bool completed,
    bool failed,
  ) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = completed
        ? _successTone(context)
        : (failed ? _errorTone(context) : accent);

    final progress = _progress;
    final percent = progress == null
        ? null
        : (progress < 0 ? 0.0 : (progress > 100 ? 100.0 : progress));
    final bigNumber = percent != null
        ? '${percent.toStringAsFixed(0)}%'
        : (completed ? '100%' : null);
    final total = _totalRows;
    final String caption;
    if (total != null) {
      caption = '${_processedRows ?? 0} de $total '
          '${total == 1 ? 'linha lida' : 'linhas lidas'}';
    } else {
      caption = completed || failed
          ? 'Leitura encerrada'
          : 'Preparando a leitura das linhas…';
    }

    final double? barValue = percent != null
        ? percent / 100
        : (completed ? 1.0 : (failed ? 0.0 : null));
    final errors = _errorCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (bigNumber != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    bigNumber,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      height: 1.0,
                      color: ThemeHelpers.textColor(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: barValue,
            minHeight: 8,
            backgroundColor: ThemeHelpers.borderLightColor(context),
            valueColor: AlwaysStoppedAnimation<Color>(tone),
          ),
        ),
        const SizedBox(height: 12),
        _statRow(
          context,
          icon: Icons.check_circle_outline_rounded,
          label: 'Importados',
          value: _successCount ?? 0,
          tone: _successTone(context),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: ThemeHelpers.borderLightColor(context),
        ),
        _statRow(
          context,
          icon: Icons.error_outline_rounded,
          label: 'Com erro',
          value: errors,
          tone: errors > 0 ? _errorTone(context) : muted,
        ),
      ],
    );
  }

  Widget _statRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Rodapé ─────────────────────────

  Widget _buildFooter(BuildContext context, Color accent) {
    final completed = _status == 'completed';
    final failed = _status == 'failed';
    final muted = ThemeHelpers.textSecondaryColor(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    const labelStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 14);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    final Widget content;
    if (_jobId == null) {
      content = Row(
        children: [
          Expanded(
            // Cancelar é neutro: o tema pinta TextButton de vermelho.
            child: TextButton(
              onPressed: _isUploading ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: muted,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: shape,
                textStyle: labelStyle,
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Cancelar', maxLines: 1, softWrap: false),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _selectedFile != null && !_isUploading
                  ? _uploadFile
                  : null,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_rounded, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _isUploading ? 'Enviando…' : 'Iniciar importação',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                shape: shape,
                textStyle: labelStyle,
                elevation: 0,
              ),
            ),
          ),
        ],
      );
    } else if (!completed && !failed) {
      // Processando: nada a confirmar — o rodapé só diz o que acontece.
      content = FilledButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: muted),
        ),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Importando… aguarde terminar',
            maxLines: 1,
            softWrap: false,
          ),
        ),
        style: FilledButton.styleFrom(
          disabledBackgroundColor: ThemeHelpers.borderLightColor(context),
          disabledForegroundColor: muted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: shape,
          textStyle: labelStyle,
        ),
      );
    } else if (completed) {
      content = FilledButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Concluir', maxLines: 1, softWrap: false),
        style: FilledButton.styleFrom(
          backgroundColor: _successTone(context),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: shape,
          textStyle: labelStyle,
          elevation: 0,
        ),
      );
    } else {
      content = OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeHelpers.textColor(context),
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: shape,
          textStyle: labelStyle,
        ),
        child: const Text('Fechar', maxLines: 1, softWrap: false),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: content,
    );
  }

  // ───────────────────────── API plumbing ─────────────────────────

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _errorMessage = null;
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage =
            'Não foi possível abrir o arquivo escolhido. Tente de novo.';
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final endpoint = ApiConstants.clientsBulkImport;
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);

      // Headers padronizados (Authorization + X-Company-ID) — paridade
      // `imobx-front` via `ApiService.buildOutboundHeaders`.
      final headers = await ApiService.instance.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      request.headers.addAll(headers);

      final fileStream = http.ByteStream(_selectedFile!.openRead());
      final fileLength = await _selectedFile!.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: _selectedFile!.path
            .split('/')
            .last
            .split(Platform.pathSeparator)
            .last,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final jobId = jsonData['jobId']?.toString();
          if (jobId != null) {
            setState(() {
              _jobId = jobId;
              _isUploading = false;
              _status = 'processing';
            });
            _startPolling(jobId);
          } else {
            setState(() {
              _errorMessage = 'O servidor recebeu a planilha, mas não '
                  'confirmou o início da importação. Tente enviar de novo.';
              _isUploading = false;
            });
          }
        } catch (_) {
          setState(() {
            _errorMessage = 'Não foi possível entender a resposta do '
                'servidor. Tente enviar de novo.';
            _isUploading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Não foi possível enviar a planilha '
              '(erro ${response.statusCode}). Confira o arquivo e tente '
              'de novo.';
          _isUploading = false;
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Não foi possível enviar a planilha. Verifique a '
            'conexão e tente de novo.';
        _isUploading = false;
      });
    }
  }

  void _startPolling(String jobId) {
    setState(() => _isPolling = true);
    _pollJobStatus(jobId);
  }

  Future<void> _pollJobStatus(String jobId) async {
    while (mounted &&
        _isPolling &&
        _status != 'completed' &&
        _status != 'failed') {
      try {
        final endpoint = ApiConstants.clientsImportJob(jobId);
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
        // Headers padronizados (Authorization + X-Company-ID) — paridade
        // `imobx-front` via `ApiService.buildOutboundHeaders`.
        final headers = await ApiService.instance.buildOutboundHeaders(
          endpoint: endpoint,
        );
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (!mounted) break;
          int? asInt(dynamic v) =>
              v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
          setState(() {
            _status = data['status']?.toString();
            _totalRows = asInt(data['totalRows']);
            _processedRows = asInt(data['processedRows']);
            // O job do back expõe `successfulImports`/`failedImports`
            // (AsyncBulkImportService); os nomes antigos ficam de reserva.
            _successCount =
                asInt(data['successfulImports'] ?? data['successCount']);
            _errorCount = asInt(data['failedImports'] ?? data['errorCount']);
            _hasErrorFile = data['hasErrorFile'] == true;
            if (_totalRows != null &&
                _processedRows != null &&
                _totalRows! > 0) {
              _progress = (_processedRows! / _totalRows!) * 100;
            } else if (data['progress'] is num) {
              _progress = (data['progress'] as num).toDouble();
            }
            if (data['status']?.toString() == 'failed') {
              final errs = data['errors'];
              if (errs is List && errs.isNotEmpty) {
                final first = errs.first;
                final msg = first is Map ? first['error'] : first;
                if (msg != null) _errorMessage = msg.toString();
              }
            }
          });

          if (_status == 'completed' || _status == 'failed') {
            setState(() => _isPolling = false);
            widget.onImportComplete?.call();
            // Igual ao web: terminou com erros e há planilha → baixa sozinho.
            if (_status == 'completed' &&
                (_errorCount ?? 0) > 0 &&
                _hasErrorFile &&
                !_autoDownloadedErrors) {
              _autoDownloadedErrors = true;
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) await _downloadErrorFile();
            }
            break;
          }
        }

        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('Erro ao verificar status do job: $e');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// `GET /clients/import-jobs/:jobId/errors` → arquivo
  /// `erros_importacao_<jobId>.xlsx`, aberto na folha de compartilhar.
  Future<void> _downloadErrorFile() async {
    final jobId = _jobId;
    if (jobId == null || _downloadingErrors) return;
    setState(() => _downloadingErrors = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await ClientService.instance.downloadImportErrors(jobId);
      if (!mounted) return;
      if (response.success && response.data != null) {
        await ClientSpreadsheet.shareBytes(
          bytes: response.data!,
          fileName: 'erros_importacao_$jobId.xlsx',
          subject: 'Planilha de erros da importação',
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Planilha de erros baixada com sucesso!'),
            backgroundColor: AppColors.status.success,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              response.message ?? 'Erro ao baixar planilha de erros.',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Não foi possível baixar a planilha de erros. Tente de novo.',
          ),
          backgroundColor: AppColors.status.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingErrors = false);
    }
  }

  /// Modelo de importação — mesmas colunas, instruções e exemplos do
  /// `generateClientTemplate` do web (`utils/excelTemplate.ts`).
  Future<void> _downloadTemplate({required bool csv}) async {
    const headers = <Object?>[
      'nome',
      'email',
      'cpf',
      'telefone_principal',
      'telefone_secundario',
      'whatsapp',
      'endereco',
      'numero',
      'complemento',
      'bairro',
      'cidade',
      'estado',
      'cep',
      'valor_minimo',
      'valor_maximo',
      'tipo_interesse',
      'observacoes',
    ];
    const comments = <Object?>[
      'Nome completo (OBRIGATÓRIO)',
      'Email (opcional)',
      'CPF apenas números, 11 dígitos (OBRIGATÓRIO)',
      'Telefone principal apenas números (OBRIGATÓRIO)',
      'Telefone secundário apenas números (opcional)',
      'WhatsApp apenas números (opcional)',
      'Nome da rua/avenida (OBRIGATÓRIO)',
      'Número do endereço (OBRIGATÓRIO)',
      'Complemento: apto, sala, etc (opcional)',
      'Bairro (OBRIGATÓRIO)',
      'Cidade (OBRIGATÓRIO)',
      'Estado: SP, RJ, MG, etc - 2 letras (OBRIGATÓRIO)',
      'CEP apenas números, 8 dígitos (OBRIGATÓRIO)',
      'Valor mínimo em números (opcional)',
      'Valor máximo em números (opcional)',
      'comprador, vendedor, locatario, locador, investidor (OBRIGATÓRIO)',
      'Observações gerais (opcional)',
    ];
    // No .xlsx os valores vão como número; no .csv, como texto.
    final examples = <List<Object?>>[
      [
        'João Silva', 'joao.silva@example.com', '12345678901', '11987654321',
        '11912345678', '11987654321', 'Rua das Flores', '123', 'Apto 401',
        'Jardim Paulista', 'São Paulo', 'SP', '01234567',
        csv ? '100000' : 100000, csv ? '500000' : 500000, 'comprador',
        'Cliente interessado em apartamentos de 2 quartos',
      ],
      [
        'Maria Oliveira', 'maria.o@example.com', '98765432100', '21998765432',
        null, '21998765432', 'Avenida Principal', '456', null, 'Centro',
        'Rio de Janeiro', 'RJ', '20000000', null, csv ? '800000' : 800000,
        'vendedor', 'Proprietária de casa no centro',
      ],
      [
        'Pedro Santos', 'pedro@example.com', '11122233344', '11999887766',
        '11988776655', '11999887766', 'Rua dos Lírios', '789', 'Casa',
        'Jardim América', 'Belo Horizonte', 'MG', '30123456',
        csv ? '200000' : 200000, csv ? '600000' : 600000, 'comprador',
        'Interessado em casas com garagem',
      ],
      [
        'Ana Costa', 'ana.costa@example.com', '55566677788', '11977665544',
        null, '11977665544', 'Av. Paulista', '1000', 'Sala 50', 'Bela Vista',
        'São Paulo', 'SP', '01310100', null, null, 'locador',
        'Proprietária de apartamento para locação',
      ],
    ];
    final rows = <List<Object?>>[headers, comments, ...examples];
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = csv
          ? ClientSpreadsheet.buildCsv(rows)
          : ClientSpreadsheet.buildXlsx(
              sheetName: 'Clientes',
              rows: rows,
              columnWidths: const [
                20, 25, 15, 15, 15, 15, 25, 8, 15, 15, 15, 5, 10, 12, 12,
                15, 40,
              ],
            );
      await ClientSpreadsheet.shareBytes(
        bytes: bytes,
        fileName: csv ? 'template_clientes.csv' : 'template_clientes.xlsx',
        subject: 'Modelo de importação de clientes',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Modelo ${csv ? 'CSV' : 'Excel'} gerado com sucesso!',
          ),
          backgroundColor: AppColors.status.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Não foi possível gerar o modelo. Tente de novo.',
          ),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }
}

// ───────────────────────── Passos ─────────────────────────

enum _StepState { todo, active, done, error }

/// Um passo do caminho de importação: selo numerado (ou ✓), título,
/// explicação curta e o conteúdo do passo; um filete liga ao próximo.
class _ImportStep extends StatelessWidget {
  const _ImportStep({
    required this.number,
    required this.title,
    required this.state,
    this.subtitle,
    this.tag,
    this.child,
    this.last = false,
  });

  final int number;
  final String title;
  final _StepState state;
  final String? subtitle;
  final String? tag;
  final Widget? child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;

    return Stack(
      children: [
        if (!last)
          Positioned(
            left: 13,
            top: 34,
            bottom: 6,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: state == _StepState.done
                    ? success.withValues(alpha: 0.45)
                    : ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepBadge(number: number, state: state),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              height: 1.25,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          if (tag != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: ThemeHelpers.borderColor(context),
                                ),
                              ),
                              child: Text(
                                tag!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10.5,
                                  color: muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (child != null) ...[
                      const SizedBox(height: 12),
                      child!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.number, required this.state});

  final int number;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final error =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final muted = ThemeHelpers.textSecondaryColor(context);

    final Color fill;
    final Color border;
    final Widget inner;
    switch (state) {
      case _StepState.done:
        fill = success;
        border = success;
        inner = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
        break;
      case _StepState.error:
        fill = error;
        border = error;
        inner = const Icon(
          Icons.priority_high_rounded,
          size: 16,
          color: Colors.white,
        );
        break;
      case _StepState.active:
        fill = accent;
        border = accent;
        inner = _number(Colors.white);
        break;
      case _StepState.todo:
        fill = isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary;
        border = ThemeHelpers.borderColor(context);
        inner = _number(muted);
        break;
    }

    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: 1.4),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: inner),
    );
  }

  Widget _number(Color color) {
    return Text(
      '$number',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        height: 1.0,
        color: color,
      ),
    );
  }
}

/// Borda tracejada ao redor de um filho — usada na área de seleção de arquivo.
class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.color,
    required this.child,
    this.radius = 20,
  });

  final Color color;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // Por cima do filho: o tracejado não some sob o fundo tingido.
    return CustomPaint(
      foregroundPainter: _DottedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  _DottedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = _dashPath(path, dashArray: const [6.0, 4.5]);
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(Path source, {required List<double> dashArray}) {
    final dest = Path();
    int i = 0;
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final length = dashArray[i % dashArray.length];
        if (draw) {
          dest.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
        i++;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
