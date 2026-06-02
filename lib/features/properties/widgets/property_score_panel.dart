import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/property_score_models.dart';
import '../utils/property_score_compact.dart';
import 'property_score_appearance.dart';

/// Painel da nota — paridade visual com `PropertyScoreDetails` (`surface='panel'`).
class PropertyScorePanel extends StatelessWidget {
  final PropertyScoreResult result;
  final bool showMethodologySummary;

  const PropertyScorePanel({
    super.key,
    required this.result,
    this.showMethodologySummary = true,
  });

  static const _dimensionMeta = {
    PropertyScoreDimensionKey.highImpact: (
      'Fundamentos',
      'Fotos, descrição, preço e dados essenciais',
    ),
    PropertyScoreDimensionKey.mediumImpact: (
      'Qualidade',
      'Composição, endereço, diferenciais e transparência',
    ),
    PropertyScoreDimensionKey.complementary: (
      'Excelência',
      'Tour, planta, título e volume de mídia',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final appearance = propertyScoreAppearance(result.level);
    final scoreTen = (result.score / 10).toStringAsFixed(1);
    final summary = propertyScoreSummaryText(result);
    final improvements = compactPropertyScoreImprovements(result);
    final high = improvements
        .where((i) => i.impact == PropertyScoreImpact.high)
        .toList();
    final medium = improvements
        .where((i) => i.impact != PropertyScoreImpact.high)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroPanel(
          score: result.score,
          scoreTen: scoreTen,
          summary: summary,
          appearance: appearance,
          muted: muted,
        ),
        const SizedBox(height: 18),
        _SectionHead(
          title: 'Por que essa nota',
          icon: Icons.trending_up_rounded,
          tone: const Color(0xFF6366F1),
          textColor: text,
        ),
        const SizedBox(height: 8),
        ...result.breakdown.map(
          (d) => _DimensionPanel(
            dimension: d,
            accent: appearance.color,
            isDark: isDark,
            textColor: text,
            muted: muted,
          ),
        ),
        const SizedBox(height: 18),
        _SectionHead(
          title: 'Como melhorar',
          icon: Icons.lightbulb_outline_rounded,
          tone: const Color(0xFFF59E0B),
          textColor: text,
        ),
        const SizedBox(height: 8),
        if (improvements.isEmpty)
          _EmptyImprovements(muted: muted)
        else ...[
          Text(
            'Próximos passos para subir a nota',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          _ImprovementFlow(
            high: high,
            medium: medium,
            textColor: text,
            isDark: isDark,
          ),
        ],
        if (showMethodologySummary) ...[
          const SizedBox(height: 18),
          _MethodologyFoot(muted: muted, textColor: text),
        ],
      ],
    );
  }
}

// ─── Hero (panel inline — sem card) ─────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  final int score;
  final String scoreTen;
  final String summary;
  final PropertyScoreAppearance appearance;
  final Color muted;

  const _HeroPanel({
    required this.score,
    required this.scoreTen,
    required this.summary,
    required this.appearance,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ScoreRing(score: score, color: appearance.color, size: 64),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'NOTA DE QUALIDADE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: muted,
                ),
              ),
              Text('·', style: TextStyle(color: muted.withValues(alpha: 0.65))),
              Text(
                scoreTen,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                  color: appearance.color,
                ),
              ),
              Text(
                '/10',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              _LevelBadge(appearance: appearance),
              SizedBox(
                width: double.infinity,
                child: Text(
                  summary,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: muted,
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

class _LevelBadge extends StatelessWidget {
  final PropertyScoreAppearance appearance;

  const _LevelBadge({required this.appearance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: appearance.bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        appearance.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: appearance.color,
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;

  const _ScoreRing({
    required this.score,
    required this.color,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final scoreTen = (score / 10).toStringAsFixed(1);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: (score.clamp(0, 100)) / 100,
          color: color,
          trackColor: ThemeHelpers.textSecondaryColor(context)
              .withValues(alpha: 0.14),
        ),
        child: Center(
          child: Text(
            scoreTen,
            style: TextStyle(
              fontSize: size * 0.22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    final sweep = 2 * math.pi * progress.clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

// ─── Seções ───────────────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tone;
  final Color textColor;

  const _SectionHead({
    required this.title,
    required this.icon,
    required this.tone,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: tone),
        ),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

class _DimensionPanel extends StatelessWidget {
  final PropertyScoreDimension dimension;
  final Color accent;
  final bool isDark;
  final Color textColor;
  final Color muted;

  const _DimensionPanel({
    required this.dimension,
    required this.accent,
    required this.isDark,
    required this.textColor,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final meta = PropertyScorePanel._dimensionMeta[dimension.key]!;
    final pct = (dimension.ratio * 100).round();
    final complete = dimension.missingFields.isEmpty;
    final barColor = complete
        ? accent
        : pct >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    Text(
                      meta.$2,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${dimension.score}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: complete ? accent : textColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '/${dimension.maxScore}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: dimension.ratio.clamp(0, 1),
              minHeight: 5,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF94A3B8).withValues(alpha: 0.22),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$pct% do eixo',
                style: TextStyle(fontSize: 10.5, color: muted),
              ),
              Text(
                complete
                    ? 'Eixo completo'
                    : '${dimension.missingFields.length} pendência(s)',
                style: TextStyle(fontSize: 10.5, color: muted),
              ),
            ],
          ),
          if (complete)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  Text(
                    'Todos os critérios deste eixo estão ok',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final field in dimension.missingFields.take(4))
                    _FieldChip(label: field.label, critical: field.critical, isDark: isDark),
                  if (dimension.missingFields.length > 4)
                    Text(
                      '+${dimension.missingFields.length - 4} critério(s)',
                      style: TextStyle(fontSize: 10.5, color: muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldChip extends StatelessWidget {
  final String label;
  final bool critical;
  final bool isDark;

  const _FieldChip({
    required this.label,
    required this.critical,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fg = critical
        ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
        : ThemeHelpers.textSecondaryColor(context);
    final bg = critical
        ? (isDark
            ? const Color(0xFFEF4444).withValues(alpha: 0.14)
            : const Color(0xFFEF4444).withValues(alpha: 0.1))
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFF94A3B8).withValues(alpha: 0.12));
    final border = critical
        ? (isDark
            ? const Color(0xFFEF4444).withValues(alpha: 0.28)
            : const Color(0xFFEF4444).withValues(alpha: 0.22))
        : (isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFF94A3B8).withValues(alpha: 0.18));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 10.5, height: 1.3, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImprovementFlow extends StatelessWidget {
  final List<PropertyScoreImprovement> high;
  final List<PropertyScoreImprovement> medium;
  final Color textColor;
  final bool isDark;

  const _ImprovementFlow({
    required this.high,
    required this.medium,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        if (high.isNotEmpty) ...[
          _GroupLabel('Alta prioridade', const Color(0xFFEF4444)),
          for (final item in high) _ImprovementPill(item: item, tone: const Color(0xFFEF4444), textColor: textColor, isDark: isDark),
        ],
        if (high.isNotEmpty && medium.isNotEmpty)
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFF94A3B8).withValues(alpha: 0.28),
          ),
        if (medium.isNotEmpty) ...[
          _GroupLabel('Também vale a pena', const Color(0xFFF59E0B)),
          for (final item in medium)
            _ImprovementPill(item: item, tone: const Color(0xFFF59E0B), textColor: textColor, isDark: isDark),
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final Color tone;

  const _GroupLabel(this.text, this.tone);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: tone,
      ),
    );
  }
}

class _ImprovementPill extends StatelessWidget {
  final PropertyScoreImprovement item;
  final Color tone;
  final Color textColor;
  final bool isDark;

  const _ImprovementPill({
    required this.item,
    required this.tone,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.08 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.28 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyImprovements extends StatelessWidget {
  final Color muted;

  const _EmptyImprovements({required this.muted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cadastro completo nos eixos principais. Continue atualizando fotos e informações para manter a nota alta.',
              style: TextStyle(fontSize: 11.5, height: 1.42, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodologyFoot extends StatelessWidget {
  final Color muted;
  final Color textColor;

  const _MethodologyFoot({required this.muted, required this.textColor});

  @override
  Widget build(BuildContext context) {
    const items = [
      'Fundamentos · 50%',
      'Qualidade · 30%',
      'Excelência · 20%',
      'Régua · 1–3 Crítico · 4–6 Regular · 7–8 Bom · 9–10 Excelente',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Como calculamos',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: items
              .map(
                (s) => Text(
                  s,
                  style: TextStyle(fontSize: 10.5, height: 1.45, color: muted),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
