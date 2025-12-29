import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';

/// Página de detalhes do documento
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

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await _documentService.getDocumentById(widget.documentId);

    if (mounted) {
      if (response.success && response.data != null) {
        setState(() {
          _document = response.data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar documento';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Detalhes do Documento',
      showBottomNavigation: false,
      actions: [
        if (_document != null)
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.documentEdit(_document!.id),
              ).then((_) => _loadDocument());
            },
            tooltip: 'Editar',
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppColors.status.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadDocument,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : _document == null
                  ? const Center(child: Text('Documento não encontrado'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card principal
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nome/Título
                                  Text(
                                    _document!.title ?? _document!.originalName,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Tipo e Status
                                  Row(
                                    children: [
                                      _buildInfoChip(
                                        context,
                                        theme,
                                        _document!.type.label,
                                        AppColors.primary.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildInfoChip(
                                        context,
                                        theme,
                                        _document!.status.label,
                                        _getStatusColor(_document!.status),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Informações do arquivo
                                  _buildInfoRow(
                                    context,
                                    theme,
                                    'Arquivo',
                                    _document!.originalName,
                                    Icons.insert_drive_file,
                                  ),
                                  _buildInfoRow(
                                    context,
                                    theme,
                                    'Tamanho',
                                    _formatFileSize(_document!.fileSize),
                                    Icons.storage,
                                  ),
                                  _buildInfoRow(
                                    context,
                                    theme,
                                    'Tipo',
                                    _document!.mimeType,
                                    Icons.info_outline,
                                  ),
                                  
                                  if (_document!.description != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Descrição',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _document!.description!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],

                                  if (_document!.notes != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Observações',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _document!.notes!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Botão de download
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // TODO: Implementar download
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Download em desenvolvimento'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.download),
                              label: const Text('Baixar Documento'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    ThemeData theme,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.active:
        return AppColors.status.success;
      case DocumentStatus.approved:
        return AppColors.status.success;
      case DocumentStatus.pendingReview:
        return AppColors.status.warning;
      case DocumentStatus.rejected:
        return AppColors.status.error;
      case DocumentStatus.archived:
        return AppColors.text.textSecondary;
      case DocumentStatus.deleted:
        return AppColors.status.error;
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

