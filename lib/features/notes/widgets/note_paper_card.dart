import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/notes_service.dart';

Color noteAccentColor(NoteListItem note, Color fallback) {
  final hex = note.color?.trim();
  if (hex != null && hex.isNotEmpty) {
    var s = hex.replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length == 8) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(v);
    }
  }
  switch (note.priority.toLowerCase()) {
    case 'urgent':
      return const Color(0xFFDC2626);
    case 'high':
      return const Color(0xFFF97316);
    case 'low':
      return const Color(0xFF64748B);
    case 'medium':
    default:
      return fallback;
  }
}

String priorityLabelPt(String raw) {
  switch (raw.toLowerCase().trim()) {
    case 'low':
      return 'Baixa';
    case 'high':
      return 'Alta';
    case 'urgent':
      return 'Urgente';
    case 'medium':
    default:
      return 'Média';
  }
}

String _relativePt(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  if (diff.inDays < 7) return 'há ${diff.inDays} d';
  return DateFormat('d MMM', 'pt_BR').format(dt);
}

String? _shortReminder(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final dt = DateTime.tryParse(raw);
  if (dt == null) return null;
  return DateFormat("d MMM · HH:mm", 'pt_BR').format(dt.toLocal());
}

/// Cartão “papel” na lista — prévia rica, sem caixa dentro de caixa.
class NotePaperCard extends StatelessWidget {
  const NotePaperCard({
    super.key,
    required this.note,
    required this.accent,
    this.onTap,
  });

  final NoteListItem note;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final noteColor = noteAccentColor(note, accent);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isUrgent = note.priority.toLowerCase() == 'urgent';
    final content = note.content?.trim() ?? '';
    final hasContent = content.isNotEmpty;
    final created = note.createdAt;
    final updated = note.updatedAt;
    final displayDate = updated ?? created;
    final wasEdited = created != null &&
        updated != null &&
        updated.difference(created).inMinutes > 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? ThemeHelpers.cardBackgroundColor(context)
                : const Color(0xFFFFFDF8),
            border: Border.all(
              color: note.isPinned
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context)
                      .withValues(alpha: isDark ? 0.22 : 0.32),
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF5A460A).withValues(alpha: 0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [noteColor, noteColor.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
              ),
              if (!isDark)
                Positioned(
                  top: 0,
                  right: 0,
                  child: CustomPaint(
                    size: const Size(20, 20),
                    painter: _PaperFoldPainter(),
                  ),
                ),
              if (!isDark)
                Positioned(
                  left: 24,
                  right: 12,
                  top: 48,
                  bottom: 56,
                  child: IgnorePointer(
                    child: CustomPaint(painter: _RuledLinesPainter()),
                  ),
                ),
              if (note.isPinned)
                const Positioned(
                  top: 10,
                  left: 12,
                  child: _PinCornerBadge(),
                ),
              if (isUrgent)
                Positioned(
                  top: 14,
                  right: 32,
                  child: Transform.rotate(
                    angle: 0.1,
                    child: const _UrgentStamp(),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  note.isPinned ? 36 : 16,
                  14,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _NoteTopBar(
                            note: note,
                            noteColor: noteColor,
                          ),
                        ),
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 20,
                          color: noteColor.withValues(alpha: 0.75),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                    ),
                    if (hasContent) ...[
                      const SizedBox(height: 8),
                      _PreviewExcerpt(
                        text: content,
                        noteColor: noteColor,
                        muted: muted,
                      ),
                    ],
                    if (note.hasClient ||
                        note.hasReminder ||
                        note.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _PreviewDetails(
                        note: note,
                        muted: muted,
                        noteColor: noteColor,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.28),
                    ),
                    const SizedBox(height: 10),
                    _PreviewFooter(
                      note: note,
                      muted: muted,
                      displayDate: displayDate,
                      wasEdited: wasEdited,
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

/// Texto direto no “papel” — só traço lateral, sem caixa interna.
class _PreviewExcerpt extends StatelessWidget {
  const _PreviewExcerpt({
    required this.text,
    required this.noteColor,
    required this.muted,
  });

  final String text;
  final Color noteColor;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 2,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: noteColor.withValues(alpha: 0.55),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                    height: 1.48,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewDetails extends StatelessWidget {
  const _PreviewDetails({
    required this.note,
    required this.muted,
    required this.noteColor,
  });

  final NoteListItem note;
  final Color muted;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];

    if (note.hasClient) {
      final name = note.clientName?.trim();
      rows.add(
        _detailLine(
          context,
          icon: Icons.person_outline_rounded,
          label: 'Cliente',
          value: name?.isNotEmpty == true ? name! : 'Vinculado',
          tint: const Color(0xFF10B981),
        ),
      );
    }

    final reminder = _shortReminder(note.reminderDate);
    if (note.hasReminder && reminder != null) {
      rows.add(
        _detailLine(
          context,
          icon: Icons.alarm_rounded,
          label: 'Lembrete',
          value: reminder,
          tint: const Color(0xFFF59E0B),
        ),
      );
    }

    if (note.imageCount > 0) {
      rows.add(
        _detailLine(
          context,
          icon: Icons.image_outlined,
          label: 'Anexos',
          value: note.imageCount == 1 ? '1 imagem' : '${note.imageCount} imagens',
          tint: noteColor,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: r,
            )),
        if (note.tags.isNotEmpty) ...[
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: note.tags.take(3).map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: noteColor.withValues(alpha: 0.28),
                  ),
                  color: noteColor.withValues(alpha: 0.06),
                ),
                child: Text(
                  t,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: noteColor,
                  ),
                ),
              );
            }).toList(),
          ),
          if (note.tags.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${note.tags.length - 3} tags',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _detailLine(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color tint,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              children: [
                TextSpan(
                  text: '$label · ',
                  style: TextStyle(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewFooter extends StatelessWidget {
  const _PreviewFooter({
    required this.note,
    required this.muted,
    required this.displayDate,
    required this.wasEdited,
  });

  final NoteListItem note;
  final Color muted;
  final DateTime? displayDate;
  final bool wasEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = note.authorName?.trim();
    final initial = (author != null && author.isNotEmpty)
        ? author[0].toUpperCase()
        : '?';

    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: muted.withValues(alpha: 0.12),
          child: Text(
            initial,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author ?? 'Autor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (displayDate != null)
                Text(
                  '${wasEdited ? 'Editada' : 'Criada'} · ${_relativePt(displayDate!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (note.wordCount > 0)
          Text(
            '${note.wordCount} pal.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _PaperFoldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, 0)
      ..lineTo(size.width, size.height)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF4EDC6), Color(0xFFF4EDC6)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RuledLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF786428).withValues(alpha: 0.07)
      ..strokeWidth = 1;
    const step = 22.0;
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PinCornerBadge extends StatelessWidget {
  const _PinCornerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Transform.rotate(
        angle: -0.35,
        child: const Icon(
          Icons.push_pin_rounded,
          size: 12,
          color: Color(0xFF7C2D12),
        ),
      ),
    );
  }
}

class _UrgentStamp extends StatelessWidget {
  const _UrgentStamp();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1.5),
      ),
      child: const Text(
        'URGENTE',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
          color: color,
        ),
      ),
    );
  }
}

class _NoteTopBar extends StatelessWidget {
  const _NoteTopBar({required this.note, required this.noteColor});

  final NoteListItem note;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _MiniChip(
          icon: Icons.flag_rounded,
          label: priorityLabelPt(note.priority),
          tone: _priorityTone(note.priority),
        ),
        if (note.hasClient)
          const _MiniChip(
            icon: Icons.person_outline_rounded,
            label: 'Cliente',
            tone: _ChipTone.success,
          ),
        if (note.hasReminder)
          const _MiniChip(
            icon: Icons.alarm_rounded,
            label: 'Lembrete',
            tone: _ChipTone.warning,
          ),
        if (note.isPinned)
          const _MiniChip(
            icon: Icons.push_pin_rounded,
            label: 'Fixada',
            tone: _ChipTone.warning,
          ),
      ],
    );
  }

  _ChipTone _priorityTone(String p) {
    switch (p.toLowerCase()) {
      case 'urgent':
        return _ChipTone.danger;
      case 'high':
        return _ChipTone.warning;
      case 'low':
        return _ChipTone.neutral;
      default:
        return _ChipTone.info;
    }
  }
}

enum _ChipTone { info, warning, success, danger, neutral }

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (tone) {
      _ChipTone.info => isDark
          ? (const Color(0xFF1E3A8A), const Color(0xFF93C5FD))
          : (const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      _ChipTone.warning => isDark
          ? (const Color(0xFF78350F), const Color(0xFFFCD34D))
          : (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      _ChipTone.success => isDark
          ? (const Color(0xFF065F46), const Color(0xFF6EE7B7))
          : (const Color(0xFFD1FAE5), const Color(0xFF065F46)),
      _ChipTone.danger => isDark
          ? (const Color(0xFF7F1D1D), const Color(0xFFFCA5A5))
          : (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      _ChipTone.neutral => isDark
          ? (Colors.white.withValues(alpha: 0.08), Colors.white70)
          : (const Color(0xFFF1F5F9), const Color(0xFF64748B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
