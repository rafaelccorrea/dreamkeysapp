import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';
import '../widgets/entity_selector.dart';

/// Página de criação/edição de documento
class CreateDocumentPage extends StatefulWidget {
  final String? documentId;

  const CreateDocumentPage({
    super.key,
    this.documentId,
  });

  @override
  State<CreateDocumentPage> createState() => _CreateDocumentPageState();
}

class _CreateDocumentPageState extends State<CreateDocumentPage> {
  final DocumentService _documentService = DocumentService.instance;
  final _formKey = GlobalKey<FormState>();
  
  File? _selectedFile;
  DocumentType? _selectedType;
  DocumentStatus? _selectedStatus;
  String? _selectedClientId;
  String? _selectedPropertyId;
  String? _selectedClientName;
  String? _selectedPropertyName;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _expiryDate;
  bool _isEncrypted = false;
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.documentId != null;
    if (_isEditing) {
      _loadDocument();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    if (widget.documentId == null) return;

    setState(() => _isLoading = true);

    final response = await _documentService.getDocumentById(widget.documentId!);

    if (mounted) {
      if (response.success && response.data != null) {
        final doc = response.data!;
        setState(() {
          _selectedType = doc.type;
          _selectedStatus = doc.status;
          _selectedClientId = doc.clientId;
          _selectedPropertyId = doc.propertyId;
          _selectedClientName = doc.client?.name;
          _selectedPropertyName = doc.property?.title;
          _titleController.text = doc.title ?? '';
          _descriptionController.text = doc.description ?? '';
          _notesController.text = doc.notes ?? '';
          _expiryDate = doc.expiryDate;
          _isEncrypted = doc.isEncrypted;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao carregar documento'),
            backgroundColor: AppColors.status.error,
          ),
        );
        Navigator.pop(context);
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        
        if (!_documentService.validateFile(file)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Arquivo muito grande! Tamanho máximo: 50MB'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedFile = file;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar arquivo: $e');
    }
  }

  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isEditing && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione um arquivo'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    // Validar vínculo
    if (!_documentService.validateBinding(_selectedClientId, _selectedPropertyId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('O documento deve estar vinculado a um cliente OU uma propriedade'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        // Atualizar documento existente
        final response = await _documentService.updateDocument(
          widget.documentId!,
          type: _selectedType,
          status: _selectedStatus,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          expiryDate: _expiryDate,
          clientId: _selectedClientId,
          propertyId: _selectedPropertyId,
          isEncrypted: _isEncrypted,
        );

        if (mounted) {
          if (response.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Documento atualizado com sucesso!'),
                backgroundColor: AppColors.status.success,
              ),
            );
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao atualizar documento'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
        }
      } else {
        // Criar novo documento
        final response = await _documentService.uploadDocument(
          file: _selectedFile!,
          type: _selectedType!,
          clientId: _selectedClientId,
          propertyId: _selectedPropertyId,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          expiryDate: _expiryDate,
          isEncrypted: _isEncrypted,
        );

        if (mounted) {
          if (response.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Documento criado com sucesso!'),
                backgroundColor: AppColors.status.success,
              ),
            );
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao criar documento'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar documento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: _isEditing ? 'Editar Documento' : 'Novo Documento',
      showBottomNavigation: false,
      body: _isLoading && _isEditing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Seleção de arquivo
                    if (!_isEditing) ...[
                      Text(
                        'Arquivo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_selectedFile == null
                            ? 'Selecionar Arquivo'
                            : _selectedFile!.path.split('/').last),
                      ),
                      if (_selectedFile != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tamanho: ${_formatFileSize(_selectedFile!.lengthSync())}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],

                    // Tipo
                    Text(
                      'Tipo de Documento *',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<DocumentType>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: DocumentType.values.map((type) {
                        return DropdownMenuItem<DocumentType>(
                          value: type,
                          child: Text(type.label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedType = value);
                      },
                      validator: (value) {
                        if (value == null) return 'Selecione o tipo';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Vínculo (Cliente OU Propriedade)
                    Text(
                      'Vincular a *',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatefulBuilder(
                      builder: (context, setStateLocal) {
                        final bindingType = _selectedClientId != null
                            ? 'client'
                            : _selectedPropertyId != null
                                ? 'property'
                                : 'client'; // Padrão: cliente
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'client', label: Text('Cliente')),
                                ButtonSegment(value: 'property', label: Text('Propriedade')),
                              ],
                              selected: {bindingType},
                              onSelectionChanged: (Set<String> newSelection) {
                                final newType = newSelection.first;
                                setState(() {
                                  if (newType == 'client') {
                                    _selectedClientId = '';
                                    _selectedPropertyId = null;
                                  } else {
                                    _selectedPropertyId = '';
                                    _selectedClientId = null;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            if (bindingType == 'client')
                              EntitySelector(
                                type: 'client',
                                selectedId: _selectedClientId,
                                selectedName: _selectedClientName,
                                onSelected: (id, name) {
                                  setState(() {
                                    _selectedClientId = id;
                                    _selectedClientName = name;
                                  });
                                },
                              ),
                            if (bindingType == 'property')
                              EntitySelector(
                                type: 'property',
                                selectedId: _selectedPropertyId,
                                selectedName: _selectedPropertyName,
                                onSelected: (id, name) {
                                  setState(() {
                                    _selectedPropertyId = id;
                                    _selectedPropertyName = name;
                                  });
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Status (apenas para edição)
                    if (_isEditing) ...[
                      Text(
                        'Status',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DocumentStatus>(
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: DocumentStatus.values.map((status) {
                          return DropdownMenuItem<DocumentStatus>(
                            value: status,
                            child: Text(status.label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedStatus = value);
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Data de vencimento
                    Text(
                      'Data de Vencimento (opcional)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _expiryDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (date != null) {
                          setState(() => _expiryDate = date);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: _expiryDate == null
                              ? 'Selecione uma data'
                              : 'Vencimento: ${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _expiryDate == null
                              ? ''
                              : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                        ),
                      ),
                    ),
                    if (_expiryDate != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _expiryDate = null);
                        },
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('Limpar data'),
                      ),
                    const SizedBox(height: 16),

                    // Criptografia
                    SwitchListTile(
                      title: const Text('Documento Criptografado'),
                      subtitle: const Text('Marque se o documento contém dados sensíveis'),
                      value: _isEncrypted,
                      onChanged: (value) {
                        setState(() => _isEncrypted = value);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),

                    // Título
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Título (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLength: 255,
                    ),
                    const SizedBox(height: 16),

                    // Descrição
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Descrição (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 3,
                      maxLength: 300,
                    ),
                    const SizedBox(height: 16),

                    // Observações
                    TextFormField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Observações (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 3,
                      maxLength: 300,
                    ),
                    const SizedBox(height: 24),

                    // Botão salvar
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveDocument,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(_isEditing ? 'Atualizar' : 'Criar Documento'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

