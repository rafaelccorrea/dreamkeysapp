import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'chat_visual.dart';

/// Campo de mensagem do chat interno (30/09/2026) — o composer do WhatsApp
/// do app no azul do chat: campo arredondado cheio (cinza de campo), clipe
/// dentro do campo, botão de enviar redondo que só acende com texto ou
/// arquivo. O campo cresce até 5 linhas e depois rola por dentro — antes
/// crescia sem limite (`maxLines: null`) e empurrava a conversa para fora da
/// tela com o teclado aberto.
class ChatInput extends StatefulWidget {
  final Function(String, {File? file}) onSend;

  /// Linhas visíveis antes de o campo rolar por dentro. A conversa baixa
  /// para 2 em paisagem com o teclado aberto (sobra pouca altura).
  final int maxLines;

  const ChatInput({
    super.key,
    required this.onSend,
    this.maxLines = 5,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  File? _selectedFile;
  String? _selectedFileSize;

  bool get _canSend =>
      _textController.text.trim().isNotEmpty || _selectedFile != null;

  void _toast(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 18,
              color: isDark
                  ? AppColors.message.errorTextDarkMode
                  : AppColors.message.errorText,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileSize = await file.length();

        // Validar tamanho (50MB)
        if (fileSize > 50 * 1024 * 1024) {
          if (mounted) {
            _toast('Arquivo muito grande. O limite é 50 MB.');
          }
          return;
        }

        if (!mounted) return;
        setState(() {
          _selectedFile = file;
          _selectedFileSize = _formatSize(fileSize);
        });
      }
    } catch (e) {
      debugPrint('[CHAT_INPUT] Erro ao selecionar arquivo: $e');
      if (mounted) {
        _toast('Não foi possível abrir o arquivo. Tente escolher de novo.');
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
        _selectedFileSize = null;
      });
    }
  }

  void _removeFile() {
    setState(() {
      _selectedFile = null;
      _selectedFileSize = null;
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
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final fill = chatFieldFill(context);
    final canSend = _canSend;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(top: chatHairline(context)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedFile != null) _buildFileChip(context),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.only(left: 14, right: 4),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: widget.maxLines,
                              keyboardType: TextInputType.multiline,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              cursorColor: chatInk(context),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                letterSpacing: -0.1,
                              ),
                              decoration: InputDecoration(
                                hintText: _selectedFile != null
                                    ? 'Legenda (opcional)'
                                    : 'Mensagem',
                                hintStyle: TextStyle(
                                  color: secondary,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 15,
                                ),
                                // O fill vive no Container: sem isto o tema
                                // global pintava um segundo fundo.
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 11.5),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          // Clipe dentro do campo, na última linha.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: IconButton(
                              onPressed: _pickFile,
                              tooltip: 'Anexar arquivo',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                LucideIcons.paperclip,
                                size: 19,
                                color: secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Semantics(
                      button: true,
                      enabled: canSend,
                      label: _selectedFile != null
                          ? 'Enviar arquivo'
                          : 'Enviar mensagem',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: canSend
                              ? chatSolid(context)
                              : chatSolid(context).withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: canSend ? _handleSend : null,
                            child: const Center(
                              child: Icon(
                                LucideIcons.arrowUp,
                                size: 21,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Arquivo escolhido, acima do campo: nome, tamanho e "remover".
  Widget _buildFileChip(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final name = _selectedFile!.path.split(RegExp(r'[\\/]')).last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: chatFieldFill(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileText, size: 20, color: chatInk(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (_selectedFileSize != null)
                  Text(
                    '$_selectedFileSize · vai junto com a mensagem',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondary, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: secondary),
            onPressed: _removeFile,
            tooltip: 'Remover arquivo',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';
    }
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return '${mb.replaceAll('.', ',')} MB';
  }
}
