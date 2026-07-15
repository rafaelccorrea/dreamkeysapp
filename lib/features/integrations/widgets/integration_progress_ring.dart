import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';

/// Anel de progresso do hero — "X/Y ativas" (versão mobile do ProgressRing
/// do hub web). Anima o arco na primeira montagem e a cada mudança de valor.
class IntegrationProgressRing extends StatelessWidget {
  final int value;
  final int total;
  final Color accent;
  final double size;
  final bool loading;

  const IntegrationProgressRing({
    super.key,
    required this.value,
    required this.total,
    required this.accent,
    this.size = 108,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pct = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    final track = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: loading ? 0 : pct),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) {
          return CustomPaint(
            painter: _RingPainter(
              progress: progress,
              trackColor: track,
              accent: accent,
              glow: accent.withValues(alpha: isDark ? 0.4 : 0.28),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loading ? '—' : '${(progress * 100).round()}%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    loading ? 'CARREGANDO' : '$value/$total ATIVAS',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color accent;
  final Color glow;

  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.accent,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;

    // Glow suave por baixo do arco (destaque do hero, sem sujeira).
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 4
      ..strokeCap = StrokeCap.round
      ..color = glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawArc(rect, start, sweep, false, glowPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = accent;
    canvas.drawArc(rect, start, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.trackColor != trackColor;
}
