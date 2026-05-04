import 'package:flutter/material.dart';
import 'theme_helpers.dart';

/// Estilo de painel elevado (gradiente + sombra) — ramos escuros idênticos ao
/// dashboard/perfil anteriores; modo claro refinado.
enum ShellElevatedPanelStyle {
  dashboard,
  profile,
}

/// Tokens partilhados para superfícies “glass” / painéis sob o shell.
/// Mantém valores exatos do tema escuro; ajusta apenas o modo claro.
class ShellVisualTokens {
  ShellVisualTokens._();

  static Color dashboardGlassFill(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white;
  }

  static Color dashboardGlassBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.08)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.44);
  }

  static Color profileGlassFill(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.055)
        : const Color(0xFFF7F8FB);
  }

  static Color profileSectionBorder(BuildContext context) {
    return ThemeHelpers.borderLightColor(context).withValues(alpha: 0.55);
  }

  static Color portfolioGlassBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.085)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.32);
  }

  static BoxDecoration inlineTileDecoration(
    BuildContext context,
    Color accent, {
    double radius = 16,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: isDark
          ? Colors.white.withValues(alpha: 0.042)
          : Colors.white,
      border: Border.all(
        color: isDark
            ? accent.withValues(alpha: 0.12)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF334155).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 4),
                spreadRadius: -5,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 1),
                spreadRadius: -1,
              ),
            ],
    );
  }

  static BoxDecoration elevatedPanelDecoration(
    BuildContext context,
    Color accent, {
    ShellElevatedPanelStyle style = ShellElevatedPanelStyle.dashboard,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius =
        style == ShellElevatedPanelStyle.profile ? 22.0 : 24.0;
    final accentBlur = style == ShellElevatedPanelStyle.profile ? 24.0 : 28.0;
    final accentDy = style == ShellElevatedPanelStyle.profile ? 12.0 : 14.0;
    final neutralBlur = style == ShellElevatedPanelStyle.profile ? 16.0 : 18.0;
    final neutralDy = style == ShellElevatedPanelStyle.profile ? 6.0 : 8.0;
    final neutralDarkAlpha =
        style == ShellElevatedPanelStyle.profile ? 0.32 : 0.35;

    if (isDark) {
      return BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF16151E),
            Color(0xFF0E0E14),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: accentBlur,
            offset: Offset(0, accentDy),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: neutralDarkAlpha),
            blurRadius: neutralBlur,
            offset: Offset(0, neutralDy),
          ),
        ],
      );
    }

    final edge = ThemeHelpers.borderColor(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFEEF1F6),
        ],
      ),
      border: Border.all(
        color: edge.withValues(alpha: 0.5),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF475569).withValues(alpha: 0.07),
          blurRadius: accentBlur * 0.78,
          offset: Offset(0, accentDy * 0.72),
          spreadRadius: -6,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.028),
          blurRadius: neutralBlur * 0.45,
          offset: Offset(0, neutralDy * 0.42),
          spreadRadius: -2,
        ),
      ],
    );
  }
}
