import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

/// Evolução por período: coluna empilhada por balde (finalizadas, canceladas
/// e o restante gerado) + linha do valor finalizado em eixo próprio.
/// Toque/arraste escolhe o balde; a leitura aparece no topo, fora do gráfico.
class PdSeriesChart extends StatefulWidget {
  const PdSeriesChart({
    super.key,
    required this.points,
    required this.granularity,
  });

  final List<ProposalsTimeseriesPoint> points;
  final String granularity;

  @override
  State<PdSeriesChart> createState() => _PdSeriesChartState();
}

class _PdSeriesChartState extends State<PdSeriesChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant PdSeriesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) _selected = null;
  }

  int _defaultIndex() {
    final pts = widget.points;
    for (var i = pts.length - 1; i >= 0; i--) {
      if (pts[i].total > 0 || pts[i].valorFinalizado > 0) return i;
    }
    return pts.length - 1;
  }

  String _periodLabel(String raw, {bool long = false}) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    switch (widget.granularity) {
      case 'month':
        return long
            ? DateFormat("MMMM 'de' yyyy", 'pt_BR').format(d)
            : DateFormat.MMM('pt_BR').format(d);
      case 'quarter':
        final q = ((d.month - 1) ~/ 3) + 1;
        return long ? '$qº trimestre de ${d.year}' : '${q}T';
      case 'year':
        return '${d.year}';
      case 'week':
        return long
            ? 'Semana de ${DateFormat('dd/MM/yyyy').format(d)}'
            : DateFormat('dd/MM').format(d);
      default:
        return long
            ? DateFormat("EEE, dd 'de' MMM", 'pt_BR').format(d)
            : DateFormat('dd/MM').format(d);
    }
  }

  void _pick(Offset local, double width) {
    final n = widget.points.length;
    if (n == 0 || width <= 0) return;
    final i = (local.dx / (width / n)).floor().clamp(0, n - 1).toInt();
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final pts = widget.points;
    final empty =
        pts.isEmpty || pts.every((p) => p.total == 0 && p.valorFinalizado == 0);
    if (empty) {
      return const PdEmptyLine('Sem propostas geradas no período.');
    }
    final sel = (_selected ?? _defaultIndex()).clamp(0, pts.length - 1).toInt();
    final p = pts[sel];
    final outras = math.max(0, p.total - p.finalizadas - p.canceladas);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Leitura do balde selecionado.
        Text(
          _periodLabel(p.periodo, long: true),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: t.muted,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                pdBrlFull.format(p.valorFinalizado),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: t.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'fechado',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: t.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(t.green, '${pdInt.format(p.finalizadas)} finalizadas', t),
            _legend(t.amber, '${pdInt.format(p.canceladas)} canceladas', t),
            _legend(t.track, '${pdInt.format(outras)} em aberto', t),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition, w),
              onHorizontalDragStart: (d) => _pick(d.localPosition, w),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition, w),
              child: SizedBox(
                width: w,
                height: 150,
                child: CustomPaint(
                  painter: _SeriesPainter(
                    points: pts,
                    selected: sel,
                    green: t.green,
                    amber: t.amber,
                    rest: t.track,
                    line: t.accent,
                    guide: t.hairline,
                    dark: t.dark,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        // Rótulos do eixo X: início, meio e fim (sem amontoar).
        Row(
          children: [
            Expanded(
              child: Text(
                _periodLabel(pts.first.periodo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _axisStyle(t),
              ),
            ),
            if (pts.length > 2)
              Expanded(
                child: Text(
                  _periodLabel(pts[pts.length ~/ 2].periodo),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _axisStyle(t),
                ),
              ),
            if (pts.length > 1)
              Expanded(
                child: Text(
                  _periodLabel(pts.last.periodo),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _axisStyle(t),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 14,
              height: 2.5,
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Linha: valor finalizado · colunas: propostas geradas',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: t.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  TextStyle _axisStyle(PdTones t) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: t.muted,
      );

  Widget _legend(Color color, String label, PdTones t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PdDot(color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
      ],
    );
  }
}

/// Traço fino do valor finalizado por balde (abertura do painel).
class PdSparkline extends StatelessWidget {
  const PdSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 44,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(values: values, color: color),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    const pad = 3.0;
    final h = size.height - pad * 2;
    final step = size.width / (values.length - 1);
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(step * i, pad + h * (1 - values[i] / maxV)),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      // Curva suave pelo ponto médio (sem ultrapassar os extremos).
      final prev = pts[i - 1];
      final cur = pts[i];
      final midX = (prev.dx + cur.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
    }
    final area = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pts.last, 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      !identical(old.values, values) || old.color != color;
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.points,
    required this.selected,
    required this.green,
    required this.amber,
    required this.rest,
    required this.line,
    required this.guide,
    required this.dark,
  });

  final List<ProposalsTimeseriesPoint> points;
  final int selected;
  final Color green;
  final Color amber;
  final Color rest;
  final Color line;
  final Color guide;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    const topPad = 10.0;
    final plotH = size.height - topPad;
    final slot = size.width / n;
    final barW = math.max(2.0, math.min(slot * 0.62, 18.0));

    final maxTotal = points.fold<int>(0, (m, p) => math.max(m, p.total));
    final maxValor =
        points.fold<double>(0, (m, p) => math.max(m, p.valorFinalizado));

    // Guias horizontais discretas (1/2 e topo).
    final guidePaint = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = topPad + plotH * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }

    // Faixa do balde selecionado.
    final selPaint = Paint()
      ..color = line.withValues(alpha: dark ? 0.10 : 0.07);
    canvas.drawRect(
      Rect.fromLTWH(slot * selected, 0, slot, size.height),
      selPaint,
    );

    // Colunas empilhadas.
    for (var i = 0; i < n; i++) {
      final p = points[i];
      if (maxTotal == 0 || p.total == 0) continue;
      final cx = slot * i + slot / 2;
      final left = cx - barW / 2;
      final h = plotH * (p.total / maxTotal);
      final fin = p.finalizadas.clamp(0, p.total).toInt();
      final canc = p.canceladas.clamp(0, p.total - fin).toInt();
      final finH = h * (fin / p.total);
      final cancH = h * (canc / p.total);
      final restH = h - finH - cancH;
      final dim = i == selected ? 1.0 : 0.72;
      var y = size.height;
      void seg(double hh, Color c) {
        if (hh <= 0) return;
        canvas.drawRect(
          Rect.fromLTWH(left, y - hh, barW, hh),
          Paint()..color = c.withValues(alpha: c.a * dim),
        );
        y -= hh;
      }

      seg(finH, green);
      seg(cancH, amber);
      seg(restH, rest);
    }

    // Linha do valor finalizado.
    if (maxValor > 0) {
      final pts = <Offset>[
        for (var i = 0; i < n; i++)
          Offset(
            slot * i + slot / 2,
            topPad + plotH * (1 - points[i].valorFinalizado / maxValor),
          ),
      ];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      final area = Path.from(path)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              line.withValues(alpha: dark ? 0.22 : 0.14),
              line.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final s = pts[selected];
      canvas.drawCircle(s, 5, Paint()..color = line);
      canvas.drawCircle(
        s,
        2.2,
        Paint()..color = dark ? const Color(0xFF13131F) : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) =>
      !identical(old.points, points) ||
      old.selected != selected ||
      old.line != line ||
      old.dark != dark;
}
