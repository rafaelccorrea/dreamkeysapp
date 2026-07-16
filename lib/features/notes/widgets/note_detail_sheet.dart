import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/notes_service.dart';
import '../pages/create_note_page.dart';
import 'note_paper_card.dart';

/// Abre detalhe da nota como popup elevado (paridade com modal do CRM web).
Future<void> showNoteDetailSheet(
  BuildContext context, {
  required NoteListItem note,
  required Color accent,
  bool canUpdate = false,
  bool canDelete = false,
  bool archived = false,
  VoidCallback? onChanged,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _NoteDetailOverlay(
        note: note,
        accent: accent,
        canUpdate: canUpdate,
        canDelete: canDelete,
        archived: archived,
        onChanged: onChanged,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class _NoteDetailOverlay extends StatefulWidget {
  const _NoteDetailOverlay({
    required this.note,
    required this.accent,
    required this.canUpdate,
    required this.canDelete,
    required this.archived,
    this.onChanged,
  });

  final NoteListItem note;
  final Color accent;
  final bool canUpdate;
  final bool canDelete;
  final bool archived;
  final VoidCallback? onChanged;

  @override
  State<_NoteDetailOverlay> createState() => _NoteDetailOverlayState();
}

class _NoteDetailOverlayState extends State<_NoteDetailOverlay> {
  late NoteListItem _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
  }

  Future<void> _mutate(
    Future<ApiResponse<NoteListItem>> Function() fn, {
    bool closeOnSuccess = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      widget.onChanged?.call();
      if (closeOnSuccess) {
        Navigator.of(context).pop();
        return;
      }
      if (res.data != null) setState(() => _note = res.data!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Falha na operação.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final noteColor = noteAccentColor(_note, widget.accent);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: mq.size.height * 0.88,
              ),
              child: Material(
                elevation: 28,
                shadowColor: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                color: isDark
                    ? ThemeHelpers.cardBackgroundColor(context)
                    : const Color(0xFFFFFDF8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [noteColor, noteColor.withValues(alpha: 0.4)],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DetailTopBar(
                          note: _note,
                          accent: widget.accent,
                          noteColor: noteColor,
                          busy: _busy,
                          canUpdate: widget.canUpdate,
                          canDelete: widget.canDelete,
                          archived: widget.archived,
                          onClose: () => Navigator.of(context).pop(),
                          onEdit: widget.canUpdate && !widget.archived
                              ? () async {
                                  if (_busy) return;
                                  final saved = await showCreateNoteSheet(
                                    context,
                                    accent: widget.accent,
                                    initial: _note,
                                  );
                                  if (saved == true && mounted) {
                                    widget.onChanged?.call();
                                    // Recarrega a nota exibida com os dados novos.
                                    await _mutate(
                                      () =>
                                          NotesService.instance.getNote(_note.id),
                                    );
                                  }
                                }
                              : null,
                          onPin: widget.canUpdate
                              ? () => _mutate(
                                    () => NotesService.instance.togglePin(_note.id),
                                  )
                              : null,
                          onArchive: widget.canUpdate && !widget.archived
                              ? () => _mutate(
                                    () => NotesService.instance.archiveNote(_note.id),
                                    closeOnSuccess: true,
                                  )
                              : null,
                          onRestore: widget.canUpdate && widget.archived
                              ? () => _mutate(
                                    () => NotesService.instance.restoreNote(_note.id),
                                    closeOnSuccess: true,
                                  )
                              : null,
                          onDelete: widget.canDelete
                              ? () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Excluir?'),
                                      content: Text('“${_note.title}”'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancelar'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Excluir'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true && mounted) {
                                    if (_busy) return;
                                    setState(() => _busy = true);
                                    final res = await NotesService.instance
                                        .deleteNote(_note.id);
                                    if (!context.mounted) return;
                                    setState(() => _busy = false);
                                    if (res.success) {
                                      widget.onChanged?.call();
                                      Navigator.of(context).pop();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            res.message ?? 'Falha ao excluir.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                            physics: const BouncingScrollPhysics(),
                            child: _DetailBody(note: _note, accent: widget.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.note,
    required this.accent,
    required this.noteColor,
    required this.busy,
    required this.canUpdate,
    required this.canDelete,
    required this.archived,
    required this.onClose,
    this.onEdit,
    this.onPin,
    this.onArchive,
    this.onRestore,
    this.onDelete,
  });

  final NoteListItem note;
  final Color accent;
  final Color noteColor;
  final bool busy;
  final bool canUpdate;
  final bool canDelete;
  final bool archived;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: noteColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: noteColor.withValues(alpha: 0.45),
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, priorityLabelPt(note.priority), noteColor),
                if (note.isPinned) _chip(context, 'Fixada', const Color(0xFFF59E0B)),
                if (note.hasReminder) _chip(context, 'Lembrete', const Color(0xFF10B981)),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (onEdit != null)
            IconButton(
              onPressed: busy ? null : onEdit,
              tooltip: 'Editar anotação',
              icon: Icon(Icons.edit_outlined, color: muted),
            ),
          if (onPin != null)
            IconButton(
              onPressed: busy ? null : onPin,
              icon: Icon(
                note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: note.isPinned ? const Color(0xFFF59E0B) : muted,
              ),
            ),
          if (onArchive != null)
            IconButton(
              onPressed: busy ? null : onArchive,
              icon: Icon(Icons.archive_outlined, color: muted),
            ),
          if (onRestore != null)
            IconButton(
              onPressed: busy ? null : onRestore,
              icon: Icon(Icons.unarchive_outlined, color: muted),
            ),
          if (onDelete != null)
            IconButton(
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.note, required this.accent});

  final NoteListItem note;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final noteColor = noteAccentColor(note, accent);
    final content = note.content?.trim() ?? '';
    final created = note.createdAt;
    final updated = note.updatedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          note.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.45,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (created != null)
              _dateChip(
                context,
                'Criada',
                _relativePt(created),
                Icons.schedule_rounded,
              ),
            if (updated != null &&
                created != null &&
                updated.difference(created).inMinutes > 1)
              _dateChip(
                context,
                'Editada',
                _relativePt(updated),
                Icons.edit_outlined,
              ),
          ],
        ),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: noteColor.withValues(alpha: 0.06),
              border: Border(
                left: BorderSide(color: noteColor.withValues(alpha: 0.5), width: 3),
              ),
            ),
            child: Text(
              content,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
        if (note.hasClient) ...[
          const SizedBox(height: 20),
          Text(
            'CLIENTE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          _clientRow(context, note, muted),
        ],
        if (note.hasReminder && (note.reminderDate?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 16),
          _dateChip(
            context,
            'Lembrete',
            _formatReminder(note.reminderDate!),
            Icons.alarm_rounded,
            accent: const Color(0xFFF59E0B),
          ),
        ],
        if (note.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: note.tags
                .map(
                  (t) => Chip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            if (note.authorName != null && note.authorName!.trim().isNotEmpty) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: muted.withValues(alpha: 0.15),
                child: Text(
                  note.authorName!.trim()[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  note.authorName!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (note.wordCount > 0)
              Text(
                '${note.wordCount} palavras',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _clientRow(BuildContext context, NoteListItem note, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.clientName != null && note.clientName!.trim().isNotEmpty)
          Text(
            note.clientName!.trim(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        if (note.clientPhone != null && note.clientPhone!.trim().isNotEmpty)
          _linkLine(
            context,
            Icons.phone_outlined,
            note.clientPhone!.trim(),
            Uri(scheme: 'tel', path: note.clientPhone!.trim()),
            muted,
          ),
        if (note.clientEmail != null && note.clientEmail!.trim().isNotEmpty)
          _linkLine(
            context,
            Icons.mail_outline_rounded,
            note.clientEmail!.trim(),
            Uri(scheme: 'mailto', path: note.clientEmail!.trim()),
            muted,
          ),
      ],
    );
  }

  Widget _linkLine(
    BuildContext context,
    IconData icon,
    String text,
    Uri uri,
    Color muted,
  ) {
    return InkWell(
      onTap: () async {
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? accent,
  }) {
    final c = accent ?? ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
        color: c.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatReminder(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat("d MMM yyyy · HH:mm", 'pt_BR').format(dt.toLocal());
  }

  String _relativePt(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'há ${diff.inHours} h';
    if (diff.inDays < 7) return 'há ${diff.inDays} d';
    return DateFormat('d MMM yyyy', 'pt_BR').format(date);
  }
}
