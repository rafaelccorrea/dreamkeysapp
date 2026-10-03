import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/file_delivery_sheet.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Permissão de importação do back (`Permission.PROPERTY_IMPORT`).
const String kPropertyImportPermission = 'property:import';

/// Dialog para exportação e importação de propriedades.
///
/// Exportar segue o web (`propertyApi.exportProperties`): `POST
/// /properties/export` com os MESMOS filtros da lista ([filters]), prévia
/// por `dryRun` (quantos imóveis vão no arquivo e com qual escopo) e entrega
/// pela folha de arquivo do app (Compartilhar / Salvar no aparelho).
/// Cada metade só aparece com a permissão do back (`property:export` /
/// `property:import`).
class ExportImportDialog extends StatefulWidget {
  const ExportImportDialog({super.key, this.filters});

  /// Filtros/aba/busca aplicados na lista — o arquivo sai com o mesmo recorte.
  final PropertyFilters? filters;

  /// Alguma das duas ações está liberada para o usuário?
  static bool isAvailable() {
    final access = ModuleAccessService.instance;
    return access.hasPermission(AppPermissions.propertyExport) ||
        access.hasPermission(kPropertyImportPermission);
  }

  @override
  State<ExportImportDialog> createState() => _ExportImportDialogState();
}

class _ExportImportDialogState extends State<ExportImportDialog> {
  final PropertyService _propertyService = PropertyService.instance;
  bool _isImporting = false;
  String? _importResult;

  bool _loadingPreview = false;
  PropertyExportPreview? _preview;
  String? _previewError;

  bool get _canExport => ModuleAccessService.instance
      .hasPermission(AppPermissions.propertyExport);
  bool get _canImport =>
      ModuleAccessService.instance.hasPermission(kPropertyImportPermission);

  @override
  void initState() {
    super.initState();
    if (_canExport) _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });
    final res = await _propertyService.previewExport(filters: widget.filters);
    if (!mounted) return;
    setState(() {
      _loadingPreview = false;
      if (res.success && res.data != null) {
        _preview = res.data;
      } else {
        _previewError = res.message ?? 'Não foi possível contar os imóveis.';
      }
    });
  }

  Future<void> _exportProperties(String format) async {
    final label = format == 'csv' ? 'CSV' : 'Excel';
    await showFileDeliverySheet(
      context,
      title: 'Exportar imóveis',
      subtitle: _preview == null
          ? 'Planilha $label'
          : 'Planilha $label · ${_countLabel(_preview!.total)}',
      paper: FileDeliveryPaper.spreadsheet,
      expectedType: format.toUpperCase(),
      generatingTitle: 'Gerando a planilha…',
      generatingHint: 'O servidor monta o arquivo com os filtros da lista.',
      readyTitle: 'Planilha pronta',
      shareSubject: 'Imóveis exportados',
      saveDialogTitle: 'Salvar planilha',
      load: () async {
        final res = await _propertyService.exportProperties(
          format: format,
          filters: widget.filters,
        );
        final file = res.data;
        if (!res.success || file == null) {
          return ApiResponse.error(
            message: res.message ?? 'Erro ao exportar',
            statusCode: res.statusCode,
            data: res.error,
          );
        }
        return ApiResponse.success(
          data: DeliverableFile(
            bytes: file.bytes,
            fileName: file.fileName,
            mimeType: file.mimeType,
          ),
          statusCode: res.statusCode,
        );
      },
    );
  }

  static String _countLabel(int total) =>
      total == 1 ? '1 imóvel' : '$total imóveis';

  Future<void> _importProperties() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _importResult = null;
      });

      final file = File(result.files.single.path!);
      final fileBytes = await file.readAsBytes();
      final response = await _propertyService.importProperties(
        fileBytes: fileBytes,
        fileName: result.files.single.name,
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        final importData = response.data!;
        setState(() {
          _importResult = 'Importação concluída!\n'
              'Total: ${importData.total}\n'
              'Sucesso: ${importData.success}\n'
              'Falhas: ${importData.failed}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${importData.success} propriedade(s) importada(s)',
            ),
            backgroundColor: AppColors.status.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao importar'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao importar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao importar propriedades')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Widget _buildPreviewLine(ThemeData theme) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (_loadingPreview) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Contando os imóveis do arquivo…',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      );
    }
    final preview = _preview;
    if (preview == null) {
      return Text(
        _previewError ?? '',
        style: theme.textTheme.bodySmall?.copyWith(color: secondary),
      );
    }
    final parts = <String>[
      '${_countLabel(preview.total)} no arquivo',
      if ((preview.scopeLabel ?? '').isNotEmpty) preview.scopeLabel!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (preview.exceedsLimit) ...[
          const SizedBox(height: 4),
          Text(
            'O arquivo sai com os primeiros ${preview.limit} imóveis. Refine '
            'os filtros da lista para exportar o restante.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.status.warning,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nothingToExport = _preview != null && _preview!.total == 0;
    final exportDisabled = _loadingPreview || nothingToExport;

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

              if (_canExport) ...[
                // Exportação
                Text(
                  'Exportar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Exporte para Excel ou CSV os imóveis com os filtros, a aba '
                  'e a busca aplicados na lista.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPreviewLine(theme),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exportDisabled
                            ? null
                            : () => _exportProperties('xlsx'),
                        icon: const Icon(Icons.file_download),
                        label: const Text('Excel (.xlsx)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exportDisabled
                            ? null
                            : () => _exportProperties('csv'),
                        icon: const Icon(Icons.file_download),
                        label: const Text('CSV (.csv)'),
                      ),
                    ),
                  ],
                ),
                if (_canImport) const SizedBox(height: 32),
              ],

              if (_canImport) ...[
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
                    label: Text(
                      _isImporting ? 'Importando...' : 'Selecionar Arquivo',
                    ),
                  ),
                ),
              ],

              if (!_canExport && !_canImport)
                Text(
                  'Sua conta não tem permissão para exportar nem importar '
                  'imóveis. Fale com o seu gestor.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
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
