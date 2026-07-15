import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/asset_models.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Cor semântica do status do patrimônio (clara/escura conforme tema).
Color assetStatusColor(BuildContext context, AssetStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case AssetStatus.available:
      return isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    case AssetStatus.inUse:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case AssetStatus.maintenance:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case AssetStatus.lost:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case AssetStatus.disposed:
    case AssetStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData assetCategoryIcon(AssetCategory category) {
  switch (category) {
    case AssetCategory.electronics:
      return LucideIcons.monitorSmartphone;
    case AssetCategory.furniture:
      return LucideIcons.armchair;
    case AssetCategory.vehicle:
      return LucideIcons.car;
    case AssetCategory.officeSupplies:
      return LucideIcons.paperclip;
    case AssetCategory.buildingEquipment:
      return LucideIcons.wrench;
    case AssetCategory.other:
      return LucideIcons.box;
  }
}

IconData assetMovementIcon(AssetMovementType type) {
  switch (type) {
    case AssetMovementType.entry:
      return LucideIcons.circlePlus;
    case AssetMovementType.exit:
      return LucideIcons.circleMinus;
    case AssetMovementType.transfer:
      return LucideIcons.arrowLeftRight;
    case AssetMovementType.statusChange:
      return LucideIcons.refreshCw;
    case AssetMovementType.maintenance:
      return LucideIcons.wrench;
    case AssetMovementType.unknown:
      return LucideIcons.history;
  }
}

/// Item da lista de patrimônio — **linha flush** (sem card/sombra), mesmo DNA
/// dos cards de Comissões: glyph tonal da categoria, info no meio e valor à
/// direita. Toca para abrir o detalhe.
class AssetCard extends StatelessWidget {
  final Asset asset;
  final VoidCallback? onTap;

  const AssetCard({super.key, required this.asset, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = assetStatusColor(context, asset.status);

    final subtitleBits = <Widget>[];
    if (asset.brandModelLabel != null) {
      subtitleBits.add(_SpecBit(
        icon: LucideIcons.tag,
        text: asset.brandModelLabel!,
        color: neutral,
      ));
    }
    if ((asset.serialNumber ?? '').trim().isNotEmpty) {
      subtitleBits.add(_SpecBit(
        icon: LucideIcons.scanBarcode,
        text: asset.serialNumber!.trim(),
        color: neutral,
      ));
    }
    if ((asset.location ?? '').trim().isNotEmpty) {
      subtitleBits.add(_SpecBit(
        icon: LucideIcons.mapPin,
        text: asset.location!.trim(),
        color: neutral,
      ));
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom:
                  BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glyph tonal da categoria.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(assetCategoryIcon(asset.category),
                    color: tone, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _StatusPill(
                            label: asset.status.label,
                            color: tone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            asset.category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      asset.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((asset.assignedToUserName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.userCheck, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Com ${asset.assignedToUserName!.trim()}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ] else if ((asset.propertyTitle ?? '')
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.building2, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              asset.propertyTitle!.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (subtitleBits.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: subtitleBits,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Valor + data de aquisição.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(asset.value),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (asset.acquisitionDate != null)
                    Text(
                      DateFormat('dd/MM/yy', 'pt_BR')
                          .format(asset.acquisitionDate!.toLocal()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini-item de metadado (ícone + texto compacto).
class _SpecBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SpecBit(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Pílula de status — tint da cor + texto na cor.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

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
      child: Text(
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
    );
  }
}
