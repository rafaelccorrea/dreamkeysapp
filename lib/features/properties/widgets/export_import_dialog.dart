import 'package:flutter/material.dart';
// import 'package:file_picker/file_picker.dart'; // TODO: Adicionar ao pubspec.yaml
import '../../../../shared/services/property_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Dialog para exportação e importação de propriedades
class ExportImportDialog extends StatefulWidget {
  const ExportImportDialog({super.key});

  @override
  State<ExportImportDialog> createState() => _ExportImportDialogState();
}

class _ExportImportDialogState extends State<ExportImportDialog> {
  final PropertyService _propertyService = PropertyService.instance;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _importResult;

  Future<void> _exportProperties(String format) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final response = await _propertyService.exportProperties(format: format);

      if (mounted) {
        if (response.success && response.data != null) {
          // TODO: Salvar arquivo usando file_saver ou similar
          // Por enquanto, apenas mostra mensagem
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exportação concluída! ${response.data!.length} bytes'),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao exportar'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao exportar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao exportar propriedades')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _importProperties() async {
    // TODO: Implementar quando file_picker for adicionado ao pubspec.yaml
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleção de arquivo será implementada. Adicione file_picker ao pubspec.yaml'),
      ),
    );
    
    // Código comentado - será implementado quando file_picker estiver disponível
    // try {
    //   final result = await FilePicker.platform.pickFiles(
    //     type: FileType.custom,
    //     allowedExtensions: ['xlsx', 'xls', 'csv'],
    //   );
    //   if (result == null || result.files.single.path == null) return;
    //   setState(() {
    //     _isImporting = true;
    //     _importResult = null;
    //   });
    //   final file = File(result.files.single.path!);
    //   final fileBytes = await file.readAsBytes();
    //   final response = await _propertyService.importProperties(
    //     fileBytes: fileBytes,
    //     fileName: result.files.single.name,
    //   );
    //   if (mounted) {
    //     if (response.success && response.data != null) {
    //       final importData = response.data!;
    //       setState(() {
    //         _importResult = 'Importação concluída!\n'
    //             'Total: ${importData.total}\n'
    //             'Sucesso: ${importData.success}\n'
    //             'Falhas: ${importData.failed}';
    //       });
    //       if (importData.errors.isNotEmpty) {
    //         ScaffoldMessenger.of(context).showSnackBar(
    //           SnackBar(
    //             content: Text('${importData.errors.length} propriedades com erro'),
    //             backgroundColor: AppColors.status.warning,
    //             duration: const Duration(seconds: 5),
    //           ),
    //         );
    //       } else {
    //         ScaffoldMessenger.of(context).showSnackBar(
    //           SnackBar(
    //             content: Text('${importData.success} propriedades importadas com sucesso!'),
    //             backgroundColor: AppColors.status.success,
    //           ),
    //         );
    //         Navigator.pop(context, true);
    //       }
    //     } else {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         SnackBar(
    //           content: Text(response.message ?? 'Erro ao importar'),
    //           backgroundColor: AppColors.status.error,
    //         ),
    //       );
    //     }
    //   }
    // } catch (e) {
    //   debugPrint('Erro ao importar: $e');
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(content: Text('Erro ao importar propriedades')),
    //     );
    //   }
    // } finally {
    //   if (mounted) {
    //     setState(() {
    //       _isImporting = false;
    //     });
    //   }
    // }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Exportar / Importar Propriedades',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Exportação
              Text(
                'Exportar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Exporte suas propriedades para Excel ou CSV',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : () => _exportProperties('xlsx'),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download),
                      label: const Text('Excel (.xlsx)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : () => _exportProperties('csv'),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download),
                      label: const Text('CSV (.csv)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Importação
              Text(
                'Importar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Importe propriedades de um arquivo Excel ou CSV',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : _importProperties,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload),
                  label: Text(_isImporting ? 'Importando...' : 'Selecionar Arquivo'),
                ),
              ),

              // Resultado da importação
              if (_importResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.status.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.status.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _importResult!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.status.success,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

