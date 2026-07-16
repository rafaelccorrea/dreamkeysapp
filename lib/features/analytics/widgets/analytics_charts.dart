// Gráficos do domínio Analytics — mesmo approach dos charts do dashboard/metas
// do app: CustomPainter próprio, cores semânticas, grid sutil, gradiente na
// cor do dado. O gráfico COMPÕE o design (informativo e estilizado, sem
// espaço morto).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';

/// Item de barra horizontal rotulada.
class BarItem {
  final String label;
  final double value;
  final String? valueLabel;
  final String? sub;
  final Color? color;

  const BarItem({
    required this.label,
    required this.value,
    this.valueLabel,
    this.sub,
    this.color,
  });
}

/// Barras horizontais rotuladas — rótulo em cima, track sutil + fill com
/// gradiente da cor semântica e valor à direita.
class HBarChart extends StatelessWidget {
  const HBarChart({
    super.key,
    required this.items,
    required this.tone,
    this.emptyMessage = 'Sem dados no período',
  });

  final List<BarItem> items;
  final Color tone;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (items.isEmpty || items.every((i) => i.value <= 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final maxValue =
        math.max(0.001, items.map((i) => i.value).fold<double>(0, math.max));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 11),
          _row(context, items[i], maxValue),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, BarItem item, double maxValue) {
    final theme = Theme.of(context);
    final barColor = item.color ?? tone;
    final ratio = (item.value / maxValue).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.valueLabel ??
                  (item.value == item.value.roundToDouble()
                      ? '${item.value.toInt()}'
                      : item.value.toStringAsFixed(1)),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: barColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(
                height: 7,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.55),
              ),
              FractionallySizedBox(
                widthFactor: math.max(ratio, 0.015),
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: [
                      barColor.withValues(alpha: 0.55),
                      barColor,
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (item.sub != null) ...[
          const SizedBox(height: 3),
          Text(
            item.sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Barras verticais compactas (série temporal) — grid horizontal sutil +
/// barras arredondadas com gradiente; dias sem movimento viram tick discreto.
class MiniBarsChart extends StatelessWidget {
  const MiniBarsChart({
    super.key,
    required this.values,
    required this.tone,
    this.height = 96,
    this.startLabel,
    this.endLabel,
  });

  final List<double> values;
  final Color tone;
  final double height;
  final String? startLabel;
  final String? endLabel;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _MiniBarsPainter(
              values: values,
              color: tone,
              gridColor: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        if (startLabel != null || endLabel != null) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                startLabel ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
              Text(
                endLabel ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiniBarsPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color gridColor;

  _MiniBarsPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        gridPaint..color = gridColor.withValues(alpha: 0.9));

    if (values.isEmpty) return;
    final maxValue = values.fold<double>(0, math.max);
    if (maxValue <= 0) return;

    final n = values.length;
    final slot = size.width / n;
    final barWidth = math.max(2.0, math.min(slot * 0.62, 14.0));

    for (var i = 0; i < n; i++) {
      final ratio = (values[i] / maxValue).clamp(0.0, 1.0).toDouble();
      final barHeight = math.max(ratio * (size.height - 6), 0.0);
      final cx = slot * i + slot / 2;
      if (barHeight <= 0.5) {
        canvas.drawCircle(
          Offset(cx, size.height - 1.5),
          1.2,
          Paint()..color = color.withValues(alpha: 0.22),
        );
        continue;
      }
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - barWidth / 2,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        const Radius.circular(3),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarsPainter old) =>
      old.values != values || old.color != color || old.gridColor != gridColor;
}

/// Série para o gráfico de linhas.
class LineSeries {
  final List<double> values;
  final Color color;
  final String label;

  const LineSeries({
    required this.values,
    required this.color,
    required this.label,
  });
}

/// Linhas suaves (1–2 séries) com grid sutil, preenchimento em gradiente na
/// primeira série e legenda embaixo — evolução de preço, série diária etc.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.height = 150,
    this.startLabel,
    this.endLabel,
  });

  final List<LineSeries> series;
  final double height;
  final String? startLabel;
  final String? endLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _LineChartPainter(
              series: series,
              gridColor: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                startLabel ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
            ),
            for (final s in series) ...[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 10, right: 4),
                decoration:
                    BoxDecoration(color: s.color, shape: BoxShape.circle),
              ),
              Text(
                s.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: secondary,
                ),
              ),
            ],
            Expanded(
              child: Text(
                endLabel ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<LineSeries> series;
  final Color gridColor;

  _LineChartPainter({required this.series, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        gridPaint..color = gridColor.withValues(alpha: 0.9));

    var maxValue = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        maxValue = math.max(maxValue, v);
      }
    }
    if (maxValue <= 0) return;

    for (var si = series.length - 1; si >= 0; si--) {
      final s = series[si];
      if (s.values.length < 2) continue;
      final n = s.values.length;
      final path = Path();
      final points = <Offset>[];
      for (var i = 0; i < n; i++) {
        final x = size.width * i / (n - 1);
        final ratio = (s.values[i] / maxValue).clamp(0.0, 1.0).toDouble();
        final y = size.height - ratio * (size.height - 8);
        points.add(Offset(x, y));
      }
      path.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < n; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
      }

      // Preenchimento em gradiente só na primeira série (evita poluição).
      if (si == 0) {
        final fill = Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: 0.20),
                s.color.withValues(alpha: 0.0),
              ],
            ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );

      // "Led" no último ponto.
      final last = points.last;
      canvas.drawCircle(
          last, 6, Paint()..color = s.color.withValues(alpha: 0.18));
      canvas.drawCircle(last, 2.8, Paint()..color = s.color);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series || old.gridColor != gridColor;
}

/// Segmento da rosca.
class DonutSegment {
  final String label;
  final double value;
  final Color color;

  const DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// Rosca com total no centro + legenda ao lado (distribuição por dispositivo,
/// share por canal…).
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    required this.centerLabel,
    this.size = 116,
  });

  final List<DonutSegment> segments;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = segments.fold<double>(0, (acc, s) => acc + s.value);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _DonutPainter(
                  segments: segments,
                  trackColor: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.55),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total == total.roundToDouble()
                        ? '${total.toInt()}'
                        : total.toStringAsFixed(1),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    centerLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in segments) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                      ),
                      Text(
                        total > 0
                            ? '${(s.value / total * 100).toStringAsFixed(0)}%'
                            : '0%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: s.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final Color trackColor;

  _DonutPainter({required this.segments, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 13.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final total = segments.fold<double>(0, (acc, s) => acc + s.value);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = s.value / total * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        math.max(sweep - 0.03, 0.01),
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments || old.trackColor != trackColor;
}

/// Gauge semicircular de score 0–100 — DNA do gauge de conversão do dashboard.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({
    super.key,
    required this.score,
    required this.tone,
    required this.label,
    this.width = 150,
  });

  final double score; // 0..100
  final Color tone;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: width / 2 + 8,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                CustomPaint(
                  size: Size(width, width / 2 + 8),
                  painter: _GaugePainter(
                    progress: (score / 100).clamp(0.0, 1.0).toDouble(),
                    color: tone,
                    trackColor: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.6),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    score.toStringAsFixed(0),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 10.0;
    final cx = size.width / 2;
    final cy = size.height - 4;
    final radius = math.min(size.width / 2, size.height) - strokeWidth / 2 - 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0.001) {
      canvas.drawArc(
        rect,
        math.pi,
        math.pi * progress,
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: math.pi,
            endAngle: math.pi * 2,
            colors: [color.withValues(alpha: 0.55), color],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      final endAngle = math.pi + math.pi * progress;
      final end = Offset(
        cx + radius * math.cos(endAngle),
        cy + radius * math.sin(endAngle),
      );
      canvas.drawCircle(
          end, strokeWidth * 0.9, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(end, strokeWidth * 0.3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Etapa visual do funil de conversão.
class FunnelStageBar {
  final String name;
  final int count;
  final double? conversionFromPrevious; // %
  final double conversionFromTotal; // %

  const FunnelStageBar({
    required this.name,
    required this.count,
    required this.conversionFromPrevious,
    required this.conversionFromTotal,
  });
}

/// Funil de conversão — barras decrescentes centradas com contagem dentro e
/// taxa de conversão entre etapas.
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.stages, required this.tone});

  final List<FunnelStageBar> stages;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (stages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'Nenhum dado do funil disponível',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final maxCount =
        math.max(1, stages.map((s) => s.count).fold<int>(0, math.max));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_downward_rounded,
                      size: 12, color: secondary.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    stages[i].conversionFromPrevious != null
                        ? '${stages[i].conversionFromPrevious!.toStringAsFixed(1).replaceAll('.', ',')}% da etapa anterior'
                        : '—',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
          _stageBar(context, stages[i], i, maxCount),
        ],
      ],
    );
  }

  Widget _stageBar(
      BuildContext context, FunnelStageBar stage, int index, int maxCount) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Largura decrescente proporcional, com piso pra legibilidade.
    final ratio = (stage.count / maxCount).clamp(0.0, 1.0).toDouble();
    final widthFactor = (0.34 + 0.66 * ratio).clamp(0.34, 1.0).toDouble();
    final opacity = 1.0 - index * 0.09;

    return Center(
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(colors: [
              tone.withValues(alpha: (isDark ? 0.32 : 0.16) * opacity),
              tone.withValues(alpha: (isDark ? 0.5 : 0.3) * opacity),
            ]),
            border: Border.all(
              color: tone.withValues(alpha: 0.4 * opacity),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  stage.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${stage.count}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
