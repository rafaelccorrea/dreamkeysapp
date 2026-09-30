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

/// `pdPlural(1, 'cancelada', 'canceladas')` → `1 cancelada`.
String pdPlural(int n, String singular, String plural) =>
    '${pdInt.format(n)} ${n == 1 ? singular : plural}';

/// Nome curto da etapa de assinatura (1 comprador, 2 proprietário, 3
/// corretor/captadores).
String pdEtapaNome(int etapa) {
  switch (etapa) {
    case 1:
      return 'Comprador';
    case 2:
      return 'Proprietário';
    default:
      return 'Corretor';
  }
}

/// Paleta resolvida por tema. O vermelho da marca é destaque (valor
/// fechado, capítulo); o significado vem das cores de status.
class PdTones {
  final bool dark;
  final Color accent;
  final Color green;

  /// Âmbar das MARCAS (barras, pontos, segmentos).
  final Color amber;

  /// Âmbar para TEXTO — o das marcas não passa contraste como letra.
  final Color amberText;
  final Color blue;
  final Color red;
  final Color purple;
  final Color text;
  final Color muted;
  final Color hairline;
  final Color track;

  /// "Em aberto" nos gráficos: neutro que se enxerga (o trilho sumia no
  /// branco e a coluna parecia vazia).
  final Color rest;

  /// Superfície da tela — vão de 2px entre segmentos e anel dos marcadores.
  final Color surface;

  const PdTones._({
    required this.dark,
    required this.accent,
    required this.green,
    required this.amber,
    required this.amberText,
    required this.blue,
    required this.red,
    required this.purple,
    required this.text,
    required this.muted,
    required this.hairline,
    required this.track,
    required this.rest,
    required this.surface,
  });

  factory PdTones.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = AppColors.status;
    final m = AppColors.message;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return PdTones._(
      dark: dark,
      accent: dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary,
      green: dark ? s.successDarkMode : s.success,
      // Âmbar das marcas no claro: o do tema (#E6B84C) some no branco e o de
      // texto (#D97706) fica colado no vermelho das excluídas (validador de
      // paleta: ΔE 14 < 15). #C98A12 separa (ΔE 19); toda legenda leva
      // rótulo + número, então o contraste 2,95:1 da marca tem alívio.
      amber: dark ? s.warningDarkMode : const Color(0xFFC98A12),
      amberText: dark ? m.warningTextDarkMode : m.warningText,
      blue: dark ? s.infoDarkMode : m.infoText,
      red: dark ? s.errorDarkMode : s.error,
      purple: dark ? s.purpleDarkMode : s.purple,
      text: ThemeHelpers.textColor(context),
      muted: muted,
      hairline: ThemeHelpers.borderLightColor(context),
      track: ThemeHelpers.borderColor(context)
          .withValues(alpha: dark ? 0.55 : 0.45),
      rest: muted.withValues(alpha: dark ? 0.40 : 0.32),
      surface: ThemeHelpers.backgroundColor(context),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.2,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                question,
                maxLines: 3,
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

/// Número de leitura (abertura, contrapropostas, prazos): o valor em tinta
/// de texto, um fio curto na cor do significado e o rótulo embaixo — a cor
/// marca, o texto informa (número colorido some no branco).
class PdFigure extends StatelessWidget {
  const PdFigure({
    super.key,
    required this.value,
    required this.label,
    this.sub,
    this.tone,
    this.size = 18,
  });

  final String value;
  final String label;
  final String? sub;
  final Color? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 16,
          height: 2.5,
          decoration: BoxDecoration(
            color: tone ?? t.track,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: t.text,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(
            sub!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
              color: t.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Figuras lado a lado, separadas por filete vertical (altura intrínseca —
/// nada de caixa com altura fixa em volta de texto).
class PdLedger extends StatelessWidget {
  const PdLedger({super.key, required this.children, this.gap = 12});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: EdgeInsets.symmetric(horizontal: gap),
                color: t.hairline,
              ),
            Expanded(child: children[i]),
          ],
        ],
      ),
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

/// Barra 100% empilhada; segmentos zerados somem e os vizinhos ficam
/// separados por um vão de 2px.
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

/// Item de legenda: ponto na cor da marca + rótulo em tinta de texto.
class PdLegendItem extends StatelessWidget {
  const PdLegendItem({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PdDot(color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado vazio de capítulo — sem caixa, mas ENSINA: o que aparece aqui e
/// como chegar lá ([hint]).
class PdEmptyLine extends StatelessWidget {
  const PdEmptyLine(this.message, {super.key, this.hint, this.icon});

  final String message;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: t.muted),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: hint == null ? t.muted : t.text,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
