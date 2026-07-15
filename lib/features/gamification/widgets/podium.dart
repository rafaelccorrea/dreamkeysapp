// Pódio (top 3) do ranking — vibrante mas dentro da gramática: cards sem
// borda lateral, sombras neutras, ouro/prata/bronze por significado.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import 'gamification_ui.dart';

final NumberFormat _pts = NumberFormat.decimalPattern('pt_BR');

/// Entrada genérica do pódio (individual ou equipe).
class PodiumEntry {
  final String title;
  final String subtitle;
  final int points;
  final int position;
  final bool isMe;

  const PodiumEntry({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.position,
    this.isMe = false,
  });
}

/// Pódio com 2º | 1º | 3º — o campeão fica maior e ao centro.
class GamPodium extends StatelessWidget {
  final List<PodiumEntry> entries;

  const GamPodium({super.key, required this.entries});

  PodiumEntry? _at(int position) {
    for (final e in entries) {
      if (e.position == position) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final first = _at(1);
    final second = _at(2);
    final third = _at(3);
    if (first == null && second == null && third == null) {
      return const SizedBox.shrink();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: second != null
              ? _PodiumColumn(entry: second, height: 92)
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: first != null
              ? _PodiumColumn(entry: first, height: 118)
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: third != null
              ? _PodiumColumn(entry: third, height: 76)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  final PodiumEntry entry;
  final double height;

  const _PodiumColumn({required this.entry, required this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = gamRankColor(context, entry.position);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isChampion = entry.position == 1;

    final initials = entry.title.trim().isEmpty
        ? '—'
        : entry.title
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar com anel na cor da medalha
        Container(
          width: isChampion ? 56 : 46,
          height: isChampion ? 56 : 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tone.withValues(alpha: isDark ? 0.34 : 0.22),
                tone.withValues(alpha: isDark ? 0.14 : 0.08),
              ],
            ),
            border: Border.all(color: tone, width: isChampion ? 2.2 : 1.6),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: isChampion ? 18 : 14,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: entry.isMe ? tone : textColor,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
        Text(
          entry.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        // Bloco do pódio
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tone.withValues(alpha: isDark ? 0.34 : 0.24),
                tone.withValues(alpha: isDark ? 0.10 : 0.06),
              ],
            ),
            border: Border(
              top: BorderSide(color: tone.withValues(alpha: 0.55), width: 2),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isChampion ? LucideIcons.crown : LucideIcons.medal,
                color: tone,
                size: isChampion ? 22 : 17,
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.position}º',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_pts.format(entry.points)} pts',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
