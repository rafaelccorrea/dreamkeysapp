import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/theme/app_colors.dart';

/// Widget para input de mensagem
class ChatInput extends StatefulWidget {
  final Function(String, {File? file}) onSend;

  const ChatInput({
    super.key,
    required this.onSend,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  File? _selectedFile;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileSize = await file.length();

        // Validar tamanho (50MB)
        if (fileSize > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Arquivo muito grande. Tamanho máximo: 50MB'),
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
      debugPrint('❌ [CHAT_INPUT] Erro ao selecionar arquivo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isNotEmpty || _selectedFile != null) {
      widget.onSend(text, file: _selectedFile);
      _textController.clear();
      setState(() {
        _selectedFile = null;
      });
    }
  }

  void _removeFile() {
    setState(() {
      _selectedFile = null;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context),
            width: 1,
          ),
        ),
        color: ThemeHelpers.backgroundColor(context),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview do arquivo selecionado
            if (_selectedFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
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
                      color: AppColors.primary.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedFile!.path.split('/').last,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          FutureBuilder<String>(
                            future: _getFileSize(_selectedFile!),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? '...',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(context),
                                    ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _removeFile,
                      tooltip: 'Remover arquivo',
                    ),
                  ],
                ),
              ),
            // Input de texto e botões
            Row(
              children: [
                // Botão de anexo
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                  tooltip: 'Anexar arquivo',
                ),
                // Campo de texto
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: _selectedFile != null
                          ? 'Adicione uma mensagem (opcional)...'
                          : 'Digite uma mensagem...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: AppColors.primary.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                // Botão de enviar
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _handleSend,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getFileSize(File file) async {
    final bytes = await file.length();
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
