import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/theme/app_colors.dart';

/// Widget para input de mensagem
class ChatInput extends StatefulWidget {
  final Function(String, {String? filePath}) onSend;

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

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _textController.clear();
    }
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
        child: Row(
          children: [
            // Botão de anexo
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () {
                // TODO: Implementar seleção de arquivo
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anexar arquivo em breve'),
                  ),
                );
              },
            ),
            // Campo de texto
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Digite uma mensagem...',
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
      ),
    );
  }
}

