import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/zezin_models.dart';

/// Bottom sheet com o histórico de conversas do Zezin — uma entrada por
/// thread, ações no próprio item (renomear / excluir), botão "Nova conversa"
/// no topo. Mesmo DNA dos sheets do app (handle + eyebrow + lista flush).
class ZezinHistorySheet extends StatefulWidget {
  const ZezinHistorySheet({
    super.key,
    required this.threads,
    required this.activeThreadId,
    required this.onSelect,
    required this.onNewConversation,
    required this.onRename,
    required this.onDelete,
  });

  final List<ZezinThreadSummary> threads;
  final String? activeThreadId;

  /// Abre a conversa no chat (o sheet fecha antes de chamar).
  final void Function(ZezinThreadSummary thread) onSelect;
  final VoidCallback onNewConversation;

  /// Persiste o novo título; retorna `true` em caso de sucesso.
  final Future<bool> Function(String threadId, String title) onRename;

  /// Exclui a conversa; retorna `true` em caso de sucesso.
  final Future<bool> Function(String threadId) onDelete;

  @override
  State<ZezinHistorySheet> createState() => _ZezinHistorySheetState();
}

class _ZezinHistorySheetState extends State<ZezinHistorySheet> {
  late List<ZezinThreadSummary> _threads;
  String? _busyThreadId;

  @override
  void initState() {
    super.initState();
    _threads = List.of(widget.threads);
  }

  Color _tone(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
  }

  /// "Hoje 14:30", "Ontem", "19 fev" — paridade com o web.
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) {
      return 'Hoje ${DateFormat('HH:mm', 'pt_BR').format(d)}';
    }
    if (day == today.subtract(const Duration(days: 1))) return 'Ontem';
    return DateFormat('d MMM', 'pt_BR').format(d);
  }

  Future<void> _handleRename(ZezinThreadSummary thread) async {
    final controller = TextEditingController(text: thread.title);
    final tone = _tone(context);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Editar título'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          cursorColor: tone,
          decoration: const InputDecoration(
            hintText: 'Título da conversa',
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tone),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();

    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == thread.title || !mounted) return;

    setState(() => _busyThreadId = thread.threadId);
    final ok = await widget.onRename(thread.threadId, title);
    if (!mounted) return;
    setState(() {
      _busyThreadId = null;
      if (ok) {
        _threads = _threads
            .map((t) =>
                t.threadId == thread.threadId ? t.copyWith(title: title) : t)
            .toList();
      }
    });
  }

  Future<void> _handleDelete(ZezinThreadSummary thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Excluir conversa'),
        content: const Text(
          'Tem certeza que deseja excluir esta conversa? '
          'Ela será removida do seu histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyThreadId = thread.threadId);
    final ok = await widget.onDelete(thread.threadId);
    if (!mounted) return;
    setState(() {
      _busyThreadId = null;
      if (ok) {
        _threads =
            _threads.where((t) => t.threadId != thread.threadId).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: secondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: tone,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: tone.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'ZEZIN · HISTÓRICO',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tone,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Suas conversas',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 20, color: secondary),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onNewConversation();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: tone,
                  side: BorderSide(color: tone.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(LucideIcons.plus, size: 17),
                label: const Text(
                  'Nova conversa',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (_threads.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 34),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [
                          tone.withValues(alpha: 0.18),
                          tone.withValues(alpha: 0.06),
                        ]),
                        border:
                            Border.all(color: tone.withValues(alpha: 0.32)),
                      ),
                      child:
                          Icon(LucideIcons.messagesSquare, color: tone, size: 24),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhuma conversa anterior',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pergunte algo ao Zezin e a conversa fica salva aqui.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                  itemCount: _threads.length,
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    final active = thread.threadId == widget.activeThreadId;
                    final busy = _busyThreadId == thread.threadId;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: busy
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                widget.onSelect(thread);
                              },
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: active
                                ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: active
                                  ? tone.withValues(alpha: 0.35)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.messageSquareText,
                                  size: 17,
                                  color: active ? tone : secondary,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        thread.title.trim().isEmpty
                                            ? 'Conversa'
                                            : thread.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color:
                                              ThemeHelpers.textColor(context),
                                          fontWeight: active
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          _formatDate(thread.updatedAt),
                                          if (thread.messageCount > 1)
                                            '${thread.messageCount} mensagens',
                                        ]
                                            .where((s) => s.isNotEmpty)
                                            .join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: secondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (busy)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: tone,
                                      ),
                                    ),
                                  )
                                else
                                  PopupMenuButton<String>(
                                    tooltip: 'Opções',
                                    icon: Icon(
                                      LucideIcons.ellipsisVertical,
                                      size: 18,
                                      color: secondary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _handleRename(thread);
                                      } else if (value == 'delete') {
                                        _handleDelete(thread);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.pencil,
                                                size: 16, color: secondary),
                                            const SizedBox(width: 10),
                                            const Text('Editar título'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              LucideIcons.trash2,
                                              size: 16,
                                              color:
                                                  theme.colorScheme.error,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Excluir conversa',
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.error,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
