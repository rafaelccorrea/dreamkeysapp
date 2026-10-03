import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_form_overview_service.dart';

/// Gráficos do painel de Fichas de Venda: donut com fatias tocáveis
/// (`DistributionDonut` do web) e evolução VGV × VGC × finalizadas
/// (`OverviewTimeseriesChart`).

const Color kOverviewVgvColor = Color(0xFF6366F1);
const Color kOverviewVgcColor = Color(0xFF10B981);
const Color kOverviewFinalizadasColor = Color(0xFFF59E0B);

/// Paleta das fatias sem cor própria (unidades).
const List<Color> kOverviewDonutPalette = [
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFF3B82F6),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
  Color(0xFF8B5CF6),
  Color(0xFFEF4444),
  Color(0xFF84CC16),
  Color(0xFF0EA5E9),
];

final NumberFormat _compactBrl = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

class OverviewDonutSlice {
  final String key;
  final String label;
  final double value;
  final Color color;

  const OverviewDonutSlice({
    required this.key,
    required this.label,
    required this.value,
    required this.color,
  });
}

// ═══ Donut ════════════════════════════════════════════════════════════════

class OverviewDonutCard extends StatelessWidget {
  const OverviewDonutCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
    required this.formatValue,
    required this.emptyText,
    this.onSliceTap,
  });

  final String title;
  final String subtitle;
  final List<OverviewDonutSlice> slices;
  final String centerLabel;
  final String centerValue;
  final String Function(double) formatValue;
  final String emptyText;

  /// `null` = fatias não clicáveis (painel recarregando).
  final ValueChanged<OverviewDonutSlice>? onSliceTap;

  List<OverviewDonutSlice> get _visible =>
      slices.where((s) => s.value > 0).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final total = visible.fold<double>(0, (s, e) => s + e.value);
    final text = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(
                children: [
                  Icon(LucideIcons.chartPie, size: 26, color: secondary),
                  const SizedBox(height: 8),
                  Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 176,
                height: 176,
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final size = Size(c.maxWidth, c.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: onSliceTap == null
                          ? null
                          : (d) {
                              final i = overviewDonutHitIndex(
                                d.localPosition,
                                size,
                                visible.map((e) => e.value).toList(),
                              );
                              if (i != null) onSliceTap!(visible[i]);
                            },
                      child: CustomPaint(
                        painter: _DonutPainter(
                          values: visible.map((e) => e.value).toList(),
                          colors: visible.map((e) => e.color).toList(),
                          track: ThemeHelpers.borderLightColor(
                            context,
                          ).withValues(alpha: 0.35),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                centerValue,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: text,
                                ),
                              ),
                              Text(
                                centerLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final s in visible)
              _LegendRow(
                slice: s,
                percent: s.value / total * 100,
                value: formatValue(s.value),
                onTap: onSliceTap == null ? null : () => onSliceTap!(s),
              ),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.percent,
    required this.value,
    this.onTap,
  });

  final OverviewDonutSlice slice;
  final double percent;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: slice.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: slice.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: slice.color,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 15, color: secondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Índice da fatia sob [p] (anel entre 62% e 100% do raio), começando no
/// topo, sentido horário. `null` fora do anel.
int? overviewDonutHitIndex(Offset p, Size size, List<double> values) {
  final total = values.fold<double>(0, (s, e) => s + e);
  if (total <= 0) return null;
  final c = size.center(Offset.zero);
  final r = math.min(size.width, size.height) / 2;
  final d = (p - c).distance;
  if (d > r || d < r * 0.62) return null;
  var a = math.atan2(p.dy - c.dy, p.dx - c.dx) + math.pi / 2;
  if (a < 0) a += 2 * math.pi;
  var acc = 0.0;
  for (var i = 0; i < values.length; i++) {
    acc += values[i] / total * 2 * math.pi;
    if (a <= acc) return i;
  }
  return values.length - 1;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
  });

  final List<double> values;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, e) => s + e);
    final r = math.min(size.width, size.height) / 2;
    final stroke = r * 0.30;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: r - stroke / 2,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (total <= 0) return;
    final gap = values.length > 1 ? 0.035 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      final draw = sweep - gap;
      if (draw > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          draw,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = colors[i],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors || old.track != track;
}

// ═══ Evolução VGV × VGC × finalizadas ═════════════════════════════════════

class OverviewTimeseriesCard extends StatefulWidget {
  const OverviewTimeseriesCard({
    super.key,
    required this.points,
    required this.periodLabel,
  });

  final List<SaleFormsOverviewTimeseriesPoint> points;

  /// "dia" | "semana" | "mês".
  final String periodLabel;

  @override
  State<OverviewTimeseriesCard> createState() => _OverviewTimeseriesCardState();
}

class _OverviewTimeseriesCardState extends State<OverviewTimeseriesCard> {
  int? _selected;

  @override
  void didUpdateWidget(covariant OverviewTimeseriesCard old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) _selected = null;
  }

  void _select(Offset local, double width) {
    final n = widget.points.length;
    if (n == 0) return;
    final step = n == 1 ? width : width / (n - 1);
    final i = n == 1 ? 0 : (local.dx / step).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final empty = pts.every((p) => p.vgv == 0 && p.vgc == 0 && p.total == 0);
    final sel = _selected == null || _selected! >= pts.length
        ? null
        : pts[_selected!];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: const [
              _SeriesKey(color: kOverviewVgvColor, label: 'VGV'),
              _SeriesKey(color: kOverviewVgcColor, label: 'VGC', dashed: true),
              _SeriesKey(
                color: kOverviewFinalizadasColor,
                label: 'Finalizadas',
                bar: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: sel == null
                ? Text(
                    empty
                        ? 'Sem movimentação no período.'
                        : 'Toque no gráfico para ver cada ${widget.periodLabel}.',
                    key: const ValueKey('hint'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  )
                : _SelectedPoint(key: ValueKey(sel.periodo), point: sel),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: empty
                ? Center(
                    child: Icon(
                      LucideIcons.chartLine,
                      size: 28,
                      color: secondary.withValues(alpha: 0.6),
                    ),
                  )
                : LayoutBuilder(
                    builder: (ctx, c) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _select(d.localPosition, c.maxWidth),
                      onHorizontalDragUpdate: (d) =>
                          _select(d.localPosition, c.maxWidth),
                      child: CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: _TimeseriesPainter(
                          points: pts,
                          selected: _selected,
                          grid: ThemeHelpers.borderLightColor(
                            context,
                          ).withValues(alpha: 0.45),
                          cursor: secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
          ),
          if (!empty && pts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  overviewShortPeriod(pts.first.periodo),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: secondary,
                  ),
                ),
                const Spacer(),
                if (pts.length > 2)
                  Text(
                    overviewShortPeriod(pts[pts.length ~/ 2].periodo),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: secondary,
                    ),
                  ),
                const Spacer(),
                if (pts.length > 1)
                  Text(
                    overviewShortPeriod(pts.last.periodo),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: secondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// '2026-07-01' → '01/07' · '2026-07' → 'jul' · outros como vierem.
String overviewShortPeriod(String raw) {
  final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (day != null) return '${day.group(3)}/${day.group(2)}';
  final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (month != null) {
    final m = int.tryParse(month.group(2)!) ?? 1;
    return DateFormat.MMM('pt_BR').format(DateTime(2000, m));
  }
  return raw;
}

class _SeriesKey extends StatelessWidget {
  const _SeriesKey({
    required this.color,
    required this.label,
    this.dashed = false,
    this.bar = false,
  });

  final Color color;
  final String label;
  final bool dashed;
  final bool bar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bar)
          Container(
            width: 8,
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else
          SizedBox(
            width: 16,
            height: 3,
            child: Row(
              children: dashed
                  ? [
                      Expanded(child: Container(color: color)),
                      const SizedBox(width: 3),
                      Expanded(child: Container(color: color)),
                    ]
                  : [Expanded(child: Container(color: color))],
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }
}

class _SelectedPoint extends StatelessWidget {
  const _SelectedPoint({super.key, required this.point});

  final SaleFormsOverviewTimeseriesPoint point;

  @override
  Widget build(BuildContext context) {
    final text = ThemeHelpers.textColor(context);
    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: text,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kOverviewVgvColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOverviewVgvColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              overviewShortPeriod(point.periodo),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: text,
              ),
            ),
          ),
          cell('VGV', _compactBrl.format(point.vgv), kOverviewVgvColor),
          cell('VGC', _compactBrl.format(point.vgc), kOverviewVgcColor),
          cell(
            'FINALIZADAS',
            '${point.finalizadas}/${point.total}',
            kOverviewFinalizadasColor,
          ),
        ],
      ),
    );
  }
}

class _TimeseriesPainter extends CustomPainter {
  _TimeseriesPainter({
    required this.points,
    required this.selected,
    required this.grid,
    required this.cursor,
  });

  final List<SaleFormsOverviewTimeseriesPoint> points;
  final int? selected;
  final Color grid;
  final Color cursor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    const top = 6.0;
    final bottom = size.height - 2;
    final h = bottom - top;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double x(int i) => n == 1 ? size.width / 2 : size.width * i / (n - 1);
    final maxVgv = points.fold<double>(0, (m, p) => math.max(m, p.vgv));
    final maxVgc = points.fold<double>(0, (m, p) => math.max(m, p.vgc));
    final maxFin = points.fold<int>(0, (m, p) => math.max(m, p.finalizadas));

    // Finalizadas: barras discretas no terço de baixo (escala própria).
    if (maxFin > 0) {
      final barW = math.max(2.0, math.min(10.0, size.width / n * 0.45));
      final paint = Paint()
        ..color = kOverviewFinalizadasColor.withValues(alpha: 0.45);
      for (var i = 0; i < n; i++) {
        final v = points[i].finalizadas;
        if (v == 0) continue;
        final bh = h * 0.35 * v / maxFin;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x(i) - barW / 2, bottom - bh, barW, bh),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          paint,
        );
      }
    }

    Path line(double Function(SaleFormsOverviewTimeseriesPoint) f, double max) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final y = max <= 0 ? bottom : bottom - h * 0.92 * f(points[i]) / max;
        if (i == 0) {
          path.moveTo(x(i), y);
        } else {
          final px = x(i - 1);
          final py = max <= 0
              ? bottom
              : bottom - h * 0.92 * f(points[i - 1]) / max;
          final mx = (px + x(i)) / 2;
          path.cubicTo(mx, py, mx, y, x(i), y);
        }
      }
      return path;
    }

    // VGV: área em degradê + linha cheia (eixo da esquerda no web).
    final vgv = line((p) => p.vgv, maxVgv);
    final area = Path.from(vgv)
      ..lineTo(x(n - 1), bottom)
      ..lineTo(x(0), bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kOverviewVgvColor.withValues(alpha: 0.22),
            kOverviewVgvColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, top, size.width, h)),
    );
    canvas.drawPath(
      vgv,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = kOverviewVgvColor,
    );

    // VGC: tracejada, escala própria (eixo da direita no web).
    final vgc = line((p) => p.vgc, maxVgc);
    final vgcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = kOverviewVgcColor;
    for (final metric in vgc.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), vgcPaint);
        d += 10;
      }
    }

    final s = selected;
    if (s != null && s < n) {
      final sx = x(s);
      canvas.drawLine(
        Offset(sx, top),
        Offset(sx, bottom),
        Paint()
          ..color = cursor
          ..strokeWidth = 1,
      );
      void dot(double value, double max, Color c) {
        final y = max <= 0 ? bottom : bottom - h * 0.92 * value / max;
        canvas.drawCircle(Offset(sx, y), 5, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(sx, y), 3.5, Paint()..color = c);
      }

      dot(points[s].vgv, maxVgv, kOverviewVgvColor);
      dot(points[s].vgc, maxVgc, kOverviewVgcColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeseriesPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.grid != grid ||
      old.cursor != cursor;
}
