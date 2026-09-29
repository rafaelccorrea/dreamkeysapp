import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

class PdSlice {
  final String label;
  final int value;
  final Color color;

  const PdSlice(this.label, this.value, this.color);
}

/// Anel de distribuição (CustomPainter) com a legenda ao lado — a legenda
/// ocupa o espaço que sobra e corta o rótulo, nunca o número.
class PdRingBreakdown extends StatelessWidget {
  const PdRingBreakdown({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
  });

  final List<PdSlice> slices;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final visible = slices.where((s) => s.value > 0).toList();
    final total = visible.fold<int>(0, (s, e) => s + e.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: CustomPaint(
            painter: _RingPainter(
              slices: visible,
              track: t.track,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        centerValue,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: t.text,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        centerLabel,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PdDot(color: s.color),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: s.value > 0 ? t.text : t.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        pdInt.format(s.value),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          total == 0
                              ? '—'
                              : '${(s.value / total * 100).round()}%',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.slices, required this.track});

  final List<PdSlice> slices;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    final total = slices.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return;
    final gap = slices.length > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = math.pi * 2 * (s.value / total);
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.slices != slices || old.track != track;
}

/// Mídia / origem (via ficha de venda vinculada): barras horizontais com
/// o líder como régua.
class PdOriginBars extends StatelessWidget {
  const PdOriginBars({super.key, required this.items});

  final List<ProposalsRankingItem> items;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final top = items.take(8).toList();
    if (top.isEmpty) {
      return const PdEmptyLine('Nenhuma proposta com mídia de origem.');
    }
    final max = top.fold<int>(0, (m, e) => math.max(m, e.total));
    final sum = top.fold<int>(0, (s, e) => s + e.total);
    return Column(
      children: [
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        top[i].label.isEmpty ? 'Sem origem' : top[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${pdInt.format(top[i].total)}'
                      '${sum > 0 ? ' · ${(top[i].total / sum * 100).round()}%' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                PdMeter(
                  fraction: max == 0 ? 0 : top[i].total / max,
                  color: i == 0 ? t.purple : t.purple.withValues(alpha: 0.55),
                  height: 5,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
