import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/notes_service.dart';

/// Bottom sheet editorial — criação `POST /notes` com o mesmo contrato do CRM web.
class CreateNoteSheet extends StatefulWidget {
  const CreateNoteSheet({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<CreateNoteSheet> createState() => _CreateNoteSheetState();
}

class _CreateNoteSheetState extends State<CreateNoteSheet> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String _priority = 'medium';
  bool _pinned = false;
  bool _submitting = false;

  static const _ink = Color(0xFF4F46E5);

  static const Map<String, String> _priorityLabels = {
    'low': 'Baixa',
    'medium': 'Média',
    'high': 'Alta',
    'urgent': 'Urgente',
  };

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final t = _title.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um título.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final res = await NotesService.instance.createNote(
      title: t,
      content: _content.text.trim().isEmpty ? null : _content.text.trim(),
      priority: _priority,
      isPinned: _pinned,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      if (mounted) Navigator.of(context).pop();
      widget.onCreated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Não foi possível criar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final mq = MediaQuery.of(context);
    final accent = isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: border.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 40,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: border.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            _ink,
                            _ink.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                      child: const Icon(Icons.post_add_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NOVA ANOTAÇÃO',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capturar ideia',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mesmas regras do painel web: título obrigatório, prioridade e pin opcionais.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: muted),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _title,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Título',
                          hintText: 'Ex.: Follow-up com cliente',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _content,
                        enabled: !_submitting,
                        minLines: 4,
                        maxLines: 8,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                        decoration: InputDecoration(
                          labelText: 'Conteúdo (opcional)',
                          alignLabelWithHint: true,
                          hintText: 'Detalhes, próximos passos, links…',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Prioridade',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _priorityLabels.entries.map((e) {
                          final on = _priority == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: on,
                            onSelected: _submitting
                                ? null
                                : (v) => setState(() => _priority = e.key),
                            selectedColor: accent.withValues(alpha: 0.22),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: on ? accent : ThemeHelpers.textColor(context),
                            ),
                            side: BorderSide(
                              color: on
                                  ? accent.withValues(alpha: 0.55)
                                  : border.withValues(alpha: 0.35),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Fixar no topo',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Equivale ao pin do CRM web.',
                          style: TextStyle(color: muted, fontSize: 12.5),
                        ),
                        value: _pinned,
                        thumbColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return accent;
                          }
                          return null;
                        }),
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _pinned = v),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(22, 10, 22, 16 + mq.padding.bottom),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: border.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: Text('Cancelar', style: TextStyle(color: muted, fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(_submitting ? 'A guardar…' : 'Criar anotação'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
