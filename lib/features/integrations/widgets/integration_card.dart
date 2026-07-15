import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/integration_model.dart';

/// Cor semântica do status de conexão (verde = conectado, âmbar = pendente).
Color integrationStatusColor(BuildContext context, bool configured) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (configured) {
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
  return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
}

/// Item da lista de integrações — **linha flush** (sem card/sombra), mesma
/// gramática do CommissionCard: glyph tonal na cor da marca da integração,
/// status pill + categoria, nome, linha de contexto e chevron para o detalhe.
class IntegrationCard extends StatelessWidget {
  final IntegrationDef def;
  final IntegrationStatusData? status;
  final bool loading;
  final VoidCallback? onTap;

  const IntegrationCard({
    super.key,
    required this.def,
    this.status,
    this.loading = false,
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

    final contextLine = status?.statusLine ?? def.descriptionFor(configured);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.1),
        highlightColor: accent.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glyph tonal na cor de marca da integração.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Icon(def.icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (loading)
                          const SkeletonBox(
                              width: 76, height: 20, borderRadius: 999)
                        else
                          _StatusPill(
                            label: configured ? 'Conectado' : 'Pendente',
                            color: tone,
                            withDot: configured,
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            def.category.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w800,
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      def.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loading ? def.tagline : contextLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: neutral.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pílula de status — tint da cor + texto na cor (+ dot quando conectado).
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
              fontSize: 11,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
