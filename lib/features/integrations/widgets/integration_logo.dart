import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/integration_model.dart';

/// **Logo plate** — renderiza o logo REAL da integração (mesmos arquivos do
/// painel web) sobre um plate que garante contraste nos dois temas:
///
/// * [IntegrationDef.logoOnBrand] `true` → glifo branco sobre plate na cor da
///   marca (gradiente sutil, como os tiles do hub web);
/// * `false` → logo colorido sobre plate BRANCO (mesmo no dark mode — logos
///   escuros como Imovelweb/Autentique nunca somem no fundo escuro).
class IntegrationLogo extends StatelessWidget {
  final IntegrationDef def;
  final double size;
  final double radius;

  const IntegrationLogo({
    super.key,
    required this.def,
    this.size = 48,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = def.accent;
    final onBrand = def.logoOnBrand;

    // Glifos de marca respiram mais; logos completos ocupam mais área.
    final glyphSize = size * (onBrand ? 0.52 : 0.68);

    final Widget logo = def.logoIsSvg
        ? SvgPicture.asset(
            def.logoAsset,
            width: glyphSize,
            height: glyphSize,
            fit: BoxFit.contain,
          )
        : Image.asset(
            def.logoAsset,
            width: glyphSize,
            height: glyphSize,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(def.icon, size: glyphSize * 0.9, color: accent),
          );

    final BoxDecoration decoration = onBrand
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent,
                Color.lerp(accent, Colors.black, 0.22)!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.34 : 0.26),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: -3,
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
                blurRadius: 9,
                offset: const Offset(0, 3),
                spreadRadius: -2,
              ),
            ],
          );

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: logo,
    );
  }
}
