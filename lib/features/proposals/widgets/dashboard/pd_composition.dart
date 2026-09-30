import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

class PdSlice {
  final String label;
  final int value;
  final Color color;

  const PdSlice(this.label, this.value, this.color);
}

/// Anel de distribuição (CustomPainter) com a legenda ao lado. Em tela
/// estreita ou fonte grande a legenda desce para baixo do anel e ganha a
/// largura toda — o rótulo nunca vira "Em proces…" e o número nunca corta.
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
    final bigText = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 340 || bigText;
        final ring = _ring(t, visible, stacked ? 124.0 : 112.0);
        final legend = _legend(t, total);
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: ring),
              const SizedBox(height: 14),
              legend,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ring,
            const SizedBox(width: 18),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  Widget _ring(PdTones t, List<PdSlice> visible, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(slices: visible, track: t.track),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
    );
  }

  Widget _legend(PdTones t, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slices.length; i++) ...[
          if (i > 0) const PdHairline(indent: 15),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                PdDot(color: slices[i].color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    slices[i].label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: slices[i].value > 0 ? t.text : t.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pdInt.format(slices[i].value),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44),
                  child: Text(
                    total == 0
                        ? '—'
                        : '${(slices[i].value / total * 100).round()}%',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    // Vão entre fatias (~2px no raio do anel), nunca contorno.
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
/// o líder como régua (líder em cor cheia, os demais em tom mais leve).
class PdOriginBars extends StatelessWidget {
  const PdOriginBars({super.key, required this.items});

  final List<ProposalsRankingItem> items;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final top = items.take(8).toList();
    if (top.isEmpty) {
      return const PdEmptyLine(
        'Nenhuma proposta com mídia de origem.',
        hint: 'A origem vem da ficha de venda vinculada à proposta — sem '
            'ficha vinculada, a proposta não entra nesta conta.',
        icon: LucideIcons.link,
      );
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
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
