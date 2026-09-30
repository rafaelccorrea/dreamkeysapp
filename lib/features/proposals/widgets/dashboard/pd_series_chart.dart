import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

/// Evolução por período em DOIS painéis sobre o mesmo eixo de tempo — em
/// cima o valor fechado (linha), embaixo as propostas geradas (colunas
/// empilhadas: finalizadas, canceladas e em aberto). Dinheiro e contagem
/// nunca dividem o mesmo gráfico: duas escalas sobrepostas inventam uma
/// correlação que não existe. Toque/arraste escolhe o balde; a leitura
/// aparece no topo, fora do gráfico, e vale para os dois painéis.
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
  static const double _valueH = 64;
  static const double _columnsH = 112;

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

  String get _bucketWord {
    switch (widget.granularity) {
      case 'week':
        return 'cada semana';
      case 'month':
        return 'cada mês';
      case 'quarter':
        return 'cada trimestre';
      case 'year':
        return 'cada ano';
      default:
        return 'cada dia';
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
      return const PdEmptyLine(
        'Sem propostas geradas no período.',
        hint: 'Quando houver propostas no recorte, a evolução aparece aqui. '
            'Troque o período no topo da tela para ver outra janela.',
        icon: LucideIcons.chartColumn,
      );
    }
    final sel = (_selected ?? _defaultIndex()).clamp(0, pts.length - 1).toInt();
    final p = pts[sel];
    final outras = math.max(0, p.total - p.finalizadas - p.canceladas);
    final maxTotal = pts.fold<int>(0, (m, e) => math.max(m, e.total));
    final maxValor =
        pts.fold<double>(0, (m, e) => math.max(m, e.valorFinalizado));
    final band = t.accent.withValues(alpha: t.dark ? 0.10 : 0.07);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Leitura do balde selecionado — valor em tinta de texto, a cor fica
        // com a marca do gráfico.
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: pdBrlFull.format(p.valorFinalizado),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: t.text,
                  ),
                ),
                TextSpan(
                  text: '  fechado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            PdLegendItem(
              color: t.green,
              label: pdPlural(p.finalizadas, 'finalizada', 'finalizadas'),
            ),
            PdLegendItem(
              color: t.amber,
              label: pdPlural(p.canceladas, 'cancelada', 'canceladas'),
            ),
            PdLegendItem(
              color: t.rest,
              label: '${pdInt.format(outras)} em aberto',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition, w),
              onHorizontalDragStart: (d) => _pick(d.localPosition, w),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition, w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _panelCaption(
                    t,
                    'Valor fechado',
                    maxValor > 0 ? 'máx. ${pdBrlCompact.format(maxValor)}' : null,
                    swatch: t.accent,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: _valueH,
                    width: w,
                    child: CustomPaint(
                      painter: _ValuePainter(
                        values: [for (final e in pts) e.valorFinalizado],
                        selected: sel,
                        line: t.accent,
                        guide: t.hairline,
                        surface: t.surface,
                        band: band,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _panelCaption(
                    t,
                    'Propostas geradas',
                    maxTotal > 0 ? 'máx. ${pdInt.format(maxTotal)}' : null,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: _columnsH,
                    width: w,
                    child: CustomPaint(
                      painter: _ColumnsPainter(
                        points: pts,
                        selected: sel,
                        green: t.green,
                        amber: t.amber,
                        rest: t.rest,
                        guide: t.hairline,
                        band: band,
                      ),
                    ),
                  ),
                ],
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
        if (pts.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.pointer, size: 13, color: t.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Toque ou arraste no gráfico para ler $_bucketWord.',
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
      ],
    );
  }

  Widget _panelCaption(
    PdTones t,
    String label,
    String? scale, {
    Color? swatch,
  }) {
    return Row(
      children: [
        if (swatch != null) ...[
          Container(
            width: 12,
            height: 2.5,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: t.muted,
            ),
          ),
        ),
        if (scale != null) ...[
          const SizedBox(width: 8),
          Text(
            scale,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: t.muted,
            ),
          ),
        ],
      ],
    );
  }

  TextStyle _axisStyle(PdTones t) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: t.muted,
      );
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
    final t = PdTones.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          color: color,
          surface: t.surface,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.surface,
  });

  final List<double> values;
  final Color color;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    const pad = 7.0;
    final h = size.height - pad * 2;
    final step = (size.width - pad) / (values.length - 1);
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
    // Área: lavado de ~10% da cor, nunca bloco saturado.
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // Ponto final com anel da superfície (legível sobre a linha).
    canvas.drawCircle(pts.last, 6, Paint()..color = surface);
    canvas.drawCircle(pts.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      !identical(old.values, values) ||
      old.color != color ||
      old.surface != surface;
}

/// Painel de cima: valor fechado por balde (linha de 2px + lavado de 10%).
class _ValuePainter extends CustomPainter {
  _ValuePainter({
    required this.values,
    required this.selected,
    required this.line,
    required this.guide,
    required this.surface,
    required this.band,
  });

  final List<double> values;
  final int selected;
  final Color line;
  final Color guide;
  final Color surface;
  final Color band;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    const topPad = 7.0;
    const bottomPad = 1.0;
    final baseY = size.height - bottomPad;
    final plotH = baseY - topPad;
    final slot = size.width / n;

    // Faixa do balde selecionado (a mesma do painel de baixo).
    canvas.drawRect(
      Rect.fromLTWH(slot * selected, 0, slot, size.height),
      Paint()..color = band,
    );

    // Guias discretas: topo e base.
    final guidePaint = Paint()
      ..color = guide
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, topPad), Offset(size.width, topPad), guidePaint);
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), guidePaint);

    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(slot * i + slot / 2, topPad + plotH * (1 - values[i] / maxV)),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    final area = Path.from(path)
      ..lineTo(pts.last.dx, baseY)
      ..lineTo(pts.first.dx, baseY)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.10));
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
    canvas.drawCircle(s, 6.5, Paint()..color = surface);
    canvas.drawCircle(s, 4.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(covariant _ValuePainter old) =>
      !identical(old.values, values) ||
      old.selected != selected ||
      old.line != line ||
      old.guide != guide ||
      old.surface != surface ||
      old.band != band;
}

/// Painel de baixo: propostas geradas por balde, colunas de até 24px com
/// topo arredondado e vão de 2px entre os segmentos.
class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.points,
    required this.selected,
    required this.green,
    required this.amber,
    required this.rest,
    required this.guide,
    required this.band,
  });

  final List<ProposalsTimeseriesPoint> points;
  final int selected;
  final Color green;
  final Color amber;
  final Color rest;
  final Color guide;
  final Color band;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    const topPad = 4.0;
    final baseY = size.height - 1;
    final plotH = baseY - topPad;
    final slot = size.width / n;
    final barW = math.max(2.0, math.min(slot * 0.62, 24.0));

    canvas.drawRect(
      Rect.fromLTWH(slot * selected, 0, slot, size.height),
      Paint()..color = band,
    );

    // Guias: topo, meio e base.
    final guidePaint = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = topPad + plotH * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }

    final maxTotal = points.fold<int>(0, (m, p) => math.max(m, p.total));
    if (maxTotal == 0) return;
    const gap = 2.0;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      if (p.total <= 0) continue;
      final left = slot * i + (slot - barW) / 2;
      final h = plotH * (p.total / maxTotal);
      final fin = p.finalizadas.clamp(0, p.total).toInt();
      final canc = p.canceladas.clamp(0, p.total - fin).toInt();
      final open = p.total - fin - canc;
      final dim = i == selected ? 1.0 : 0.78;
      final segs = <(int, Color)>[
        (fin, green),
        (canc, amber),
        (open, rest),
      ].where((s) => s.$1 > 0).toList();
      // Os vãos saem da altura da coluna, sem deformar a proporção.
      final usable = math.max(0.0, h - gap * (segs.length - 1));
      var y = baseY;
      for (var k = 0; k < segs.length; k++) {
        final hh = usable * (segs[k].$1 / p.total);
        if (hh <= 0) continue;
        final rect = Rect.fromLTWH(left, y - hh, barW, hh);
        final color = segs[k].$2;
        final paint = Paint()..color = color.withValues(alpha: color.a * dim);
        final isTop = k == segs.length - 1;
        if (isTop && barW >= 6 && hh >= 4) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: const Radius.circular(4),
              topRight: const Radius.circular(4),
            ),
            paint,
          );
        } else {
          canvas.drawRect(rect, paint);
        }
        y -= hh + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnsPainter old) =>
      !identical(old.points, points) ||
      old.selected != selected ||
      old.green != green ||
      old.amber != amber ||
      old.rest != rest ||
      old.guide != guide ||
      old.band != band;
}
