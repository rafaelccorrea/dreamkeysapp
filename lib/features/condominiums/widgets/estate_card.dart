import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/shimmer_image.dart';
import 'estate_shared.dart';

/// Chip informativo do corpo do card.
class EstateCardChip {
  final IconData icon;
  final String label;
  final Color Function(BuildContext) tone;

  const EstateCardChip({
    required this.icon,
    required this.label,
    required this.tone,
  });
}

/// Card rico de condomínio/empreendimento — hero com foto (status + contagem
/// de fotos em overlay), corpo com chips, descrição e ações NO PRÓPRIO item
/// (editar/excluir), como manda o padrão flush do app.
class EstateCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int photoCount;
  final bool isActive;
  final String locationLine;
  final String? zipCode;
  final List<EstateCardChip> chips;
  final String? description;
  final DateTime? updatedAt;
  final IconData fallbackIcon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const EstateCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.photoCount,
    required this.isActive,
    required this.locationLine,
    this.zipCode,
    required this.chips,
    this.description,
    this.updatedAt,
    required this.fallbackIcon,
    required this.accent,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone =
        isActive ? EstateTones.green(context) : EstateTones.amber(context);
    final hasActions = onEdit != null || onDelete != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: accent.withValues(alpha: 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(context, statusTone, isDark),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chips.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final chip in chips)
                            EstateMiniPill(
                              label: chip.label,
                              icon: chip.icon,
                              tone: chip.tone(context),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    if ((description ?? '').trim().isNotEmpty) ...[
                      Text(
                        description!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: updatedAt != null
                              ? Row(
                                  children: [
                                    Icon(LucideIcons.history,
                                        size: 12, color: secondary),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'Atualizado em '
                                        '${DateFormat('dd/MM/yyyy', 'pt_BR').format(updatedAt!.toLocal())}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: secondary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (hasActions) ...[
                          if (onEdit != null)
                            _actionButton(
                              context,
                              icon: LucideIcons.pencil,
                              tooltip: 'Editar',
                              tone: accent,
                              onTap: onEdit!,
                            ),
                          if (onDelete != null) ...[
                            const SizedBox(width: 8),
                            _actionButton(
                              context,
                              icon: LucideIcons.trash2,
                              tooltip: 'Excluir',
                              tone: EstateTones.danger(context),
                              onTap: onDelete!,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, Color statusTone, bool isDark) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 132,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            ShimmerImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: _fallbackHero(context, isDark),
            )
          else
            _fallbackHero(context, isDark),
          // Sombra inferior para o nome respirar sobre a foto.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.62),
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _overlayPill(
                      context,
                      icon: isActive
                          ? LucideIcons.circleCheckBig
                          : LucideIcons.circleOff,
                      label: isActive ? 'Ativo' : 'Inativo',
                      tone: statusTone,
                    ),
                    const Spacer(),
                    _overlayPill(
                      context,
                      icon: LucideIcons.images,
                      label: '$photoCount',
                      tone: Colors.white,
                      glass: true,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    height: 1.1,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                if (locationLine.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(LucideIcons.mapPin,
                          size: 11, color: Colors.white70),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          (zipCode ?? '').trim().isNotEmpty
                              ? '$locationLine · CEP ${zipCode!.trim()}'
                              : locationLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackHero(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.30 : 0.18),
            accent.withValues(alpha: isDark ? 0.10 : 0.06),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 40,
          color: accent.withValues(alpha: isDark ? 0.65 : 0.5),
        ),
      ),
    );
  }

  Widget _overlayPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tone,
    bool glass = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: glass
            ? Colors.black.withValues(alpha: 0.42)
            : tone.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 16, color: tone),
          ),
        ),
      ),
    );
  }
}
