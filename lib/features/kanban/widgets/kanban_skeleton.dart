import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Skeleton do quadro Kanban / funil — alinhado ao layout “flat” da página (margens, sem rodapé de loading).
class KanbanSkeleton extends StatelessWidget {
  const KanbanSkeleton({super.key});

  double _gutterH(BuildContext context) {
    final p = MediaQuery.paddingOf(context);
    return math.max(math.max(p.left, p.right), 10.0);
  }

  Color _accent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  @override
  Widget build(BuildContext context) {
    final gutter = _gutterH(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final accent = _accent(context);
    final border = ThemeHelpers.borderColor(context);
    final subtleFill = ThemeHelpers.cardBackgroundColor(context);

    return ColoredBox(
      color: ThemeHelpers.backgroundColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Bloco hero (título / contexto) ---
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: 48,
                      height: 48,
                      borderRadius: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 11, width: 120, borderRadius: 4),
                          const SizedBox(height: 8),
                          SkeletonBox(height: 22, width: double.infinity, borderRadius: 6),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            height: 13,
                            width: math.min(
                              MediaQuery.sizeOf(context).width - gutter * 2 - 72,
                              280,
                            ),
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SkeletonBox(height: 30, width: 96, borderRadius: 999),
                    SkeletonBox(height: 30, width: 72, borderRadius: 999),
                    SkeletonBox(height: 30, width: 110, borderRadius: 999),
                  ],
                ),
                const SizedBox(height: 16),
                SkeletonBox(height: 52, width: double.infinity, borderRadius: 12),
                const SizedBox(height: 18),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: border.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),

          // --- Ferramentas (funil / projeto / filtros) ---
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 22, height: 22, borderRadius: 6),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SkeletonBox(height: 44, borderRadius: 10),
                    ),
                    const SizedBox(width: 10),
                    SkeletonBox(width: 44, height: 44, borderRadius: 12),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 42, borderRadius: 10)),
                    const SizedBox(width: 10),
                    SkeletonBox(width: 44, height: 42, borderRadius: 10),
                  ],
                ),
              ],
            ),
          ),

          // --- Cabeçalho do quadro ---
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 22, height: 22, borderRadius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SkeletonBox(height: 18, width: 160, borderRadius: 4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SkeletonBox(height: 13, width: 200, borderRadius: 4),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: border.withValues(alpha: 0.38),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // --- Colunas ---
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final usable = math.max(0.0, constraints.maxWidth - gutter * 2);
                final colViewportH =
                    constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                        ? math.max(48.0, constraints.maxHeight)
                        : 200.0;
                const gap = 10.0;
                const minCol = 240.0;
                final threeFit = (usable - gap * 2) / 3 >= minCol;
                final colW = threeFit
                    ? (usable - gap * 2) / 3
                    : math.max(minCol, 272.0);

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, bottom + 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(3, (i) {
                      return Padding(
                        padding: EdgeInsets.only(right: i < 2 ? gap : 0),
                        child: SizedBox(
                          width: colW,
                          height: colViewportH,
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            clipBehavior: Clip.hardEdge,
                            child: _ColumnSkeleton(
                              width: colW,
                              accent: accent,
                              border: border,
                              subtleFill: subtleFill,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnSkeleton extends StatelessWidget {
  const _ColumnSkeleton({
    required this.width,
    required this.accent,
    required this.border,
    required this.subtleFill,
  });

  final double width;
  final Color accent;
  final Color border;
  final Color subtleFill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 22, height: 22, borderRadius: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 17, width: double.infinity, borderRadius: 4),
                    const SizedBox(height: 6),
                    SkeletonBox(height: 12, width: 120, borderRadius: 4),
                  ],
                ),
              ),
              SkeletonBox(height: 18, width: 24, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: accent.withValues(alpha: 0.22)),
          const SizedBox(height: 10),
          _TaskSkeletonLine(subtleFill: subtleFill, border: border),
          const SizedBox(height: 10),
          _TaskSkeletonLine(subtleFill: subtleFill, border: border),
          const SizedBox(height: 12),
          SkeletonBox(height: 40, borderRadius: 12),
        ],
      ),
    );
  }
}

class _TaskSkeletonLine extends StatelessWidget {
  const _TaskSkeletonLine({
    required this.subtleFill,
    required this.border,
  });

  final Color subtleFill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: subtleFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 15, width: double.infinity, borderRadius: 4),
          const SizedBox(height: 8),
          SkeletonBox(height: 13, width: double.infinity, borderRadius: 4),
          const SizedBox(height: 6),
          SkeletonBox(height: 13, width: 140, borderRadius: 4),
          const SizedBox(height: 10),
          Row(
            children: [
              SkeletonBox(width: 56, height: 20, borderRadius: 6),
              const Spacer(),
              SkeletonBox(width: 22, height: 22, borderRadius: 11),
            ],
          ),
        ],
      ),
    );
  }
}
