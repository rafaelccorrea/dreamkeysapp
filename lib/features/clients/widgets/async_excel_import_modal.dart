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
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              _buildHeader(context, accent, theme),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: _jobId == null
                      ? _buildSelectionStage(context, accent)
                      : _buildProcessingStage(context, accent, theme),
                ),
              ),
              _buildFooter(context, accent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.upload_file_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importar clientes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _jobId == null
                      ? 'Suba uma planilha .xlsx, .xls ou .csv para iniciar'
                      : 'Acompanhe o processamento em tempo real',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Fechar',
            onPressed: (_isUploading || _isPolling) && _status != 'completed'
                ? null
                : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionStage(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final fileName = _fileName(_selectedFile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _isUploading ? null : _selectFile,
          borderRadius: BorderRadius.circular(20),
          child: DottedBorder(
            color: _selectedFile != null
                ? accent
                : ThemeHelpers.borderColor(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                color: _selectedFile != null
                    ? accent.withValues(alpha: 0.06)
                    : ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Icon(
                      _selectedFile != null
                          ? Icons.check_circle_rounded
                          : Icons.cloud_upload_rounded,
                      size: 28,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedFile != null
                        ? 'Arquivo selecionado'
                        : 'Toque para escolher um arquivo',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (fileName != null)
                    FutureBuilder<int>(
                      future: _selectedFile?.length(),
                      builder: (context, snapshot) {
                        final size = snapshot.data;
                        return Text(
                          size == null
                              ? fileName
                              : '$fileName · ${_bytesPretty(size)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    )
                  else
                    Text(
                      'Aceitamos arquivos .xlsx, .xls ou .csv com cabeçalho.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _selectFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(
                      _selectedFile != null
                          ? 'Trocar arquivo'
                          : 'Escolher arquivo',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildTemplateCard(context, accent),
        const SizedBox(height: 14),
        _buildHintCard(context, accent),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildErrorBanner(context, _errorMessage!),
        ],
      ],
    );
  }

  /// "Template (Opcional)" do web: modelo com as colunas que a importação
  /// entende, uma linha de instruções e exemplos.
  Widget _buildTemplateCard(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Modelo de planilha (opcional)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Baixe o modelo com as colunas esperadas, a linha de instruções '
            'e exemplos de preenchimento.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploading
                      ? null
                      : () => _downloadTemplate(csv: false),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text(
                    'Excel (.xlsx)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploading
                      ? null
                      : () => _downloadTemplate(csv: true),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text(
                    'CSV (.csv)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHintCard(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withValues(alpha: 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
            child: Icon(Icons.info_outline_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona a importação',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Após enviar, processamos as linhas em segundo plano. '
                  'Você pode acompanhar o status aqui mesmo. Linhas com erro '
                  'serão sinalizadas e poderão ser revisadas depois.',
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
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.status.error.withValues(alpha: 0.08),
        border: Border.all(
          color: AppColors.status.error.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppColors.status.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.status.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingStage(
    BuildContext context,
    Color accent,
    ThemeData theme,
  ) {
    final completed = _status == 'completed';
    final failed = _status == 'failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: completed
                          ? AppColors.status.success.withValues(alpha: 0.14)
                          : failed
                              ? AppColors.status.error.withValues(alpha: 0.14)
                              : accent.withValues(alpha: 0.10),
                    ),
                    child: Icon(
                      completed
                          ? Icons.check_circle_outline
                          : failed
                              ? Icons.error_outline
                              : Icons.sync_rounded,
                      color: completed
                          ? AppColors.status.success
                          : failed
                              ? AppColors.status.error
                              : accent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      completed
                          ? 'Importação concluída'
                          : failed
                              ? 'Falha na importação'
                              : 'Processando importação',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progress! / 100,
                    minHeight: 8,
                    backgroundColor:
                        ThemeHelpers.borderLightColor(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completed
                          ? AppColors.status.success
                          : failed
                              ? AppColors.status.error
                              : accent,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_progress!.toStringAsFixed(0)}% concluído',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: _statBadge(
                      context,
                      label: 'Linhas',
                      value: _totalRows == null
                          ? '—'
                          : '${_processedRows ?? 0}/$_totalRows',
                      color: accent,
                      icon: Icons.list_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBadge(
                      context,
                      label: 'Sucessos',
                      value: (_successCount ?? 0).toString(),
                      color: AppColors.status.success,
                      icon: Icons.check_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBadge(
                      context,
                      label: 'Erros',
                      value: (_errorCount ?? 0).toString(),
                      color: (_errorCount ?? 0) > 0
                          ? AppColors.status.error
                          : ThemeHelpers.textSecondaryColor(context),
                      icon: Icons.error_outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (completed && (_errorCount ?? 0) > 0 && _hasErrorFile) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _downloadingErrors ? null : _downloadErrorFile,
            icon: _downloadingErrors
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(
              _downloadingErrors
                  ? 'Baixando…'
                  : 'Baixar planilha de erros',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (failed) ...[
          const SizedBox(height: 12),
          _buildErrorBanner(
            context,
            _errorMessage ?? 'Não foi possível concluir a importação.',
          ),
        ],
      ],
    );
  }

  Widget _statBadge(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Color accent) {
    final completed = _status == 'completed';
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: (_isUploading || _isPolling) && !completed
                  ? null
                  : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(completed ? 'Fechar' : 'Cancelar'),
            ),
          ),
          if (_jobId == null) ...[
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
                label: Text(
                  _isUploading ? 'Enviando…' : 'Iniciar importação',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
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
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao selecionar arquivo: ${e.toString()}';
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
              _errorMessage = 'Erro: Job ID não retornado';
              _isUploading = false;
            });
          }
        } catch (e) {
          setState(() {
            _errorMessage = 'Erro ao processar resposta: ${e.toString()}';
            _isUploading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'Erro ao fazer upload do arquivo (${response.statusCode})';
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro: ${e.toString()}';
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
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao baixar planilha de erros: $e'),
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
            'Template ${csv ? 'CSV' : 'XLSX'} baixado com sucesso!',
          ),
          backgroundColor: AppColors.status.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar o modelo: $e'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }
}

/// Borda tracejada ao redor de um filho — usada no card de seleção de arquivo.
class DottedBorder extends StatelessWidget {
  const DottedBorder({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(color: color),
      child: child,
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  _DottedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
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
      oldDelegate.color != color;
}
