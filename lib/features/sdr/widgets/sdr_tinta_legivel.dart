import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Contraste mínimo de TEXTO (WCAG AA, texto normal).
const double _kContrasteMinimo = 4.5;

final Map<(int, bool), Color> _cache = <(int, bool), Color>{};

/// Tinta de TEXTO (e ícone pequeno) legível a partir de um token de status.
///
/// No modo claro os tons de status da casa ficam em ~3:1 no branco
/// (`status.green` 3,05; `message.successText` 3,3; `message.warningText`
/// 3,2; `status.info` 3,3) — o dono exige contraste real. Aqui o token é
/// misturado com a cor de texto do tema (`ThemeHelpers.textColor`) só o
/// bastante para passar de 4,5:1 contra a superfície clara mais escura onde
/// o texto pousa (`background.backgroundTertiary`, fill de chip e campo) —
/// logo também no branco e no `backgroundSecondary`. Continua sendo o mesmo
/// matiz do token (sem hex novo); no escuro os tokens já passam e voltam
/// como vieram.
///
/// Fundos, trilhos e preenchimentos SEM texto em cima podem seguir no tom de
/// status puro; preenchimento COM texto (botão, selo) usa esta tinta.
Color sdrTintaLegivel(BuildContext context, Color tom) {
  final escuro = Theme.of(context).brightness == Brightness.dark;
  return _cache.putIfAbsent((tom.toARGB32(), escuro), () {
    final fundo = escuro
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final texto = ThemeHelpers.textColor(context);
    for (var passo = 0; passo <= 50; passo++) {
      final c = Color.lerp(tom, texto, passo / 50)!;
      if (_contraste(c, fundo) >= _kContrasteMinimo) return c;
    }
    return texto;
  });
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final escuro = la > lb ? lb : la;
  return (claro + 0.05) / (escuro + 0.05);
}
