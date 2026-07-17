import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/integration_model.dart';
import 'integration_logo.dart';

/// Cor semântica do status de conexão (verde = conectada, âmbar = pendente).
Color integrationStatusColor(BuildContext context, bool configured) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (configured) {
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
  return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
}

/// **Card rico da integração** — espelha o card do hub web: logo REAL no
/// plate de marca, categoria discreta, status pill viva (Conectada com dot /
/// Pendente âmbar), nome, tagline curta, feature pills e CTA de detalhe.
/// Sombra neutra ([ThemeHelpers.cardShadow]) e cantos generosos.
class IntegrationCard extends StatelessWidget {
  final IntegrationDef def;
  final IntegrationStatusData? status;
  final VoidCallback? onTap;

  const IntegrationCard({
    super.key,
    required this.def,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final accent = def.accent;
    final configured = status?.configured ?? false;
    final tone = integrationStatusColor(context, configured);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: accent.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IntegrationLogo(def: def, size: 48, radius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  def.category.label.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: neutral.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                label: configured ? 'Conectada' : 'Pendente',
                                color: tone,
                                withDot: configured,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            def.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              height: 1.15,
                              letterSpacing: -0.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            def.tagline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in def.features.take(3))
                            _FeaturePill(label: f, isDark: isDark),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            accent.withValues(alpha: isDark ? 0.20 : 0.10),
                      ),
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pílula de feature — discreta, neutra, como as chips do card web.
class _FeaturePill extends StatelessWidget {
  final String label;
  final bool isDark;

  const _FeaturePill({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Pílula de status — tint da cor + texto na cor (+ dot vivo quando conectada).
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool withDot;

  const _StatusPill({
    required this.label,
    required this.color,
    this.withDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
