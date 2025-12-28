import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Modal para importação assíncrona de clientes via Excel
class AsyncExcelImportModal extends StatefulWidget {
  final Function()? onImportComplete;

  const AsyncExcelImportModal({
    super.key,
    this.onImportComplete,
  });

  @override
  State<AsyncExcelImportModal> createState() => _AsyncExcelImportModalState();
}

class _AsyncExcelImportModalState extends State<AsyncExcelImportModal> {
  
  File? _selectedFile;
  String? _jobId;
  bool _isUploading = false;
  bool _isPolling = false;
  String? _errorMessage;
  
  // Status do job
  String? _status;
  int? _totalRows;
  int? _processedRows;
  int? _successCount;
  int? _errorCount;
  double? _progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.primary.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file,
                    color: AppColors.primary.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Importar Clientes (Excel)',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isUploading || _isPolling ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_jobId == null) ...[
                      // Seleção de arquivo
                      Text(
                        'Selecione o arquivo Excel (.xlsx, .xls)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: ThemeHelpers.cardBackgroundColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ThemeHelpers.borderLightColor(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.insert_drive_file,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedFile?.path.split('/').last ?? 
                                _selectedFile?.path.split('\\').last ??
                                'Nenhum arquivo selecionado',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _selectedFile != null
                                      ? ThemeHelpers.textColor(context)
                                      : ThemeHelpers.textSecondaryColor(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _isUploading ? null : _selectFile,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Selecionar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.status.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.status.error,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppColors.status.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.status.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ] else ...[
                      // Status do processamento
                      Text(
                        'Processando Importação',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_progress != null) ...[
                        LinearProgressIndicator(
                          value: _progress! / 100,
                          backgroundColor: ThemeHelpers.borderLightColor(context),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_progress!.toStringAsFixed(0)}% concluído',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_totalRows != null && _processedRows != null) ...[
                        _buildStatusItem(
                          context,
                          theme,
                          'Linhas Processadas',
                          '$_processedRows / $_totalRows',
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_successCount != null) ...[
                        _buildStatusItem(
                          context,
                          theme,
                          'Sucessos',
                          '$_successCount',
                          color: AppColors.status.success,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_errorCount != null && _errorCount! > 0) ...[
                        _buildStatusItem(
                          context,
                          theme,
                          'Erros',
                          '$_errorCount',
                          color: AppColors.status.error,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_status == 'completed') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.status.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.status.success,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppColors.status.success,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Importação concluída com sucesso!',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.status.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_errorCount != null && _errorCount! > 0) ...[
                          const SizedBox(height: 16),
                          CustomButton(
                            text: 'Baixar Planilha de Erros',
                            icon: Icons.download,
                            onPressed: _downloadErrorFile,
                          ),
                        ],
                      ] else if (_status == 'failed') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.status.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.status.error,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error,
                                color: AppColors.status.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Falha na importação',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.status.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            // Botões
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_isUploading || _isPolling) && _status != 'completed'
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_status == 'completed' ? 'Fechar' : 'Cancelar'),
                    ),
                  ),
                  if (_jobId == null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: CustomButton(
                        text: 'Importar',
                        icon: Icons.upload,
                        onPressed: _selectedFile != null && !_isUploading
                            ? _uploadFile
                            : null,
                        isLoading: _isUploading,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildStatusItem(
    BuildContext context,
    ThemeData theme,
    String label,
    String value, {
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color ?? ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
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
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _errorMessage = 'Token de autenticação não encontrado';
          _isUploading = false;
        });
        return;
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.clientsBulkImport}');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';

      // Adicionar arquivo
      final fileStream = http.ByteStream(_selectedFile!.openRead());
      final fileLength = await _selectedFile!.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: _selectedFile!.path.split('/').last.split('\\').last,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
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
          _errorMessage = 'Erro ao fazer upload do arquivo (${response.statusCode})';
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
    setState(() {
      _isPolling = true;
    });

    _pollJobStatus(jobId);
  }

  Future<void> _pollJobStatus(String jobId) async {
    while (_isPolling && _status != 'completed' && _status != 'failed') {
      try {
        final token = await SecureStorageService.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          setState(() {
            _errorMessage = 'Token de autenticação não encontrado';
            _isPolling = false;
          });
          break;
        }

        final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.clientsImportJob(jobId)}');
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          setState(() {
            _status = data['status']?.toString();
            _totalRows = data['totalRows'] as int?;
            _processedRows = data['processedRows'] as int?;
            _successCount = data['successCount'] as int?;
            _errorCount = data['errorCount'] as int?;
            
            if (_totalRows != null && _processedRows != null && _totalRows! > 0) {
              _progress = (_processedRows! / _totalRows!) * 100;
            }
          });

          if (_status == 'completed' || _status == 'failed') {
            setState(() {
              _isPolling = false;
            });
            if (widget.onImportComplete != null) {
              widget.onImportComplete!();
            }
            break;
          }
        }

        // Aguardar 2 segundos antes da próxima verificação
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('Erro ao verificar status do job: $e');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _downloadErrorFile() async {
    if (_jobId == null) return;

    try {
      // TODO: Implementar download do arquivo de erros
      // Por enquanto, apenas mostra um snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Download de erros em desenvolvimento'),
            backgroundColor: AppColors.status.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao baixar arquivo: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }
}

