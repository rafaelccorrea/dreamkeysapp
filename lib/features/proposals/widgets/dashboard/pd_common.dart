import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Peças comuns do Dashboard de Fichas de Proposta (prefixo `Pd`).

final NumberFormat pdBrlCompact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat pdBrlFull = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 0,
);
final NumberFormat pdInt = NumberFormat.decimalPattern('pt_BR');

/// `12.5` → `12,5%` · `40.0` → `40%`.
String pdPercent(double v) {
  final s = v.toStringAsFixed(1).replaceAll('.', ',');
  return '${s.endsWith(',0') ? s.substring(0, s.length - 2) : s}%';
}

/// `3.0` → `3d` · `2.5` → `2,5d`.
String pdDays(double v) {
  final s = v.toStringAsFixed(1).replaceAll('.', ',');
  return '${s.endsWith(',0') ? s.substring(0, s.length - 2) : s}d';
}

/// Paleta resolvida por tema. O vermelho da marca é destaque (valor
/// fechado, capítulo); o significado vem das cores de status.
class PdTones {
  final bool dark;
  final Color accent;
  final Color green;
  final Color amber;
  final Color blue;
  final Color red;
  final Color purple;
  final Color text;
  final Color muted;
  final Color hairline;
  final Color track;

  const PdTones._({
    required this.dark,
    required this.accent,
    required this.green,
    required this.amber,
    required this.blue,
    required this.red,
    required this.purple,
    required this.text,
    required this.muted,
    required this.hairline,
    required this.track,
  });

  factory PdTones.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = AppColors.status;
    return PdTones._(
      dark: dark,
      accent: dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary,
      green: dark ? s.successDarkMode : s.success,
      // O âmbar do tema é claro demais sobre branco; no claro, escurece
      // para manter legibilidade de texto e barras finas.
      amber: dark ? s.warningDarkMode : const Color(0xFFC98A12),
      blue: dark ? s.infoDarkMode : const Color(0xFF2F6FBF),
      red: dark ? s.errorDarkMode : s.error,
      purple: dark ? s.purpleDarkMode : s.purple,
      text: ThemeHelpers.textColor(context),
      muted: ThemeHelpers.textSecondaryColor(context),
      hairline: ThemeHelpers.borderLightColor(context),
      track: ThemeHelpers.borderColor(context)
          .withValues(alpha: dark ? 0.55 : 0.45),
    );
  }
}

/// Filete de largura total que separa os capítulos (layout flush).
class PdHairline extends StatelessWidget {
  const PdHairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: indent),
      color: ThemeHelpers.borderLightColor(context),
    );
  }
}

/// Abertura de capítulo: numeral na cor da marca + título + a pergunta que
/// o capítulo responde. Sem caixa, sem ícone em pastilha.
class PdChapterHeader extends StatelessWidget {
  const PdChapterHeader({
    super.key,
    required this.number,
    required this.title,
    required this.question,
    this.trailing,
  });

  final int number;
  final String title;
  final String question;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            number.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: t.accent,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

/// Barra horizontal simples (trilho + preenchimento proporcional).
class PdMeter extends StatelessWidget {
  const PdMeter({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 6,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: t.track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmento de uma barra 100% empilhada.
class PdSegment {
  final int value;
  final Color color;

  const PdSegment(this.value, this.color);
}

/// Barra 100% empilhada; segmentos zerados somem.
class PdStackedBar extends StatelessWidget {
  const PdStackedBar({
    super.key,
    required this.segments,
    this.height = 8,
  });

  final List<PdSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final visible = segments.where((s) => s.value > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: visible.isEmpty
            ? ColoredBox(color: t.track)
            : Row(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: visible[i].value,
                      child: ColoredBox(color: visible[i].color),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Ponto de legenda.
class PdDot extends StatelessWidget {
  const PdDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Estado vazio de capítulo (texto discreto, sem caixa).
class PdEmptyLine extends StatelessWidget {
  const PdEmptyLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }
}
