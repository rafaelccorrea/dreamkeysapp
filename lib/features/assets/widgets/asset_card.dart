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
    final tone = assetStatusColor(context, asset.situacao);

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
                            label: asset.situacao.label,
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
                    if ((asset.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        asset.description!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    // Quem está com o item — a informação que a pessoa procura
                    // primeiro. Avatar de iniciais na cor da situação; sem
                    // ninguém, dito com todas as letras (não some).
                    _HolderLine(
                      holder: (asset.assignedToUserName ?? '').trim(),
                      foto: asset.assignedToUserAvatar,
                      propertyTitle: (asset.propertyTitle ?? '').trim(),
                      tone: tone,
                      neutral: neutral,
                    ),
                    if (subtitleBits.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: subtitleBits,
                      ),
                    ],
                    if (asset.createdAt != null) ...[
                      const SizedBox(height: 7),
                      _CadastroLine(asset: asset, neutral: neutral),
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
                  if (asset.acquisitionDate != null) ...[
                    Text(
                      DateFormat('dd/MM/yy', 'pt_BR')
                          .format(asset.acquisitionDate!.toLocal()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                    // Idade do bem: o que a data sozinha não conta de bate-pronto.
                    Text(
                      _idadeDoBem(asset.acquisitionDate!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsável pelo item: avatar de iniciais + nome; ou o imóvel; ou "sem
/// responsável" — a linha existe sempre, para o card não mudar de altura.
class _HolderLine extends StatelessWidget {
  final String holder;
  /// Foto do responsável (URL resolvida); sem foto = iniciais.
  final String? foto;
  final String propertyTitle;
  final Color tone;
  final Color neutral;

  const _HolderLine({
    required this.holder,
    this.foto,
    required this.propertyTitle,
    required this.tone,
    required this.neutral,
  });

  String get _iniciais {
    final partes = holder.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '';
    final a = partes.first[0];
    final b = partes.length > 1 ? partes.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);

    if (holder.isNotEmpty) {
      final iniciais = Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tone.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        child: Text(
          _iniciais,
          style: TextStyle(
            color: tone,
            fontWeight: FontWeight.w900,
            fontSize: 9,
            letterSpacing: 0.3,
            height: 1.0,
          ),
        ),
      );
      final temFoto = (foto ?? '').trim().isNotEmpty;
      return Row(
        children: [
          // A foto real quando existe; iniciais enquanto carrega ou se falhar.
          if (temFoto)
            SizedBox(
              width: 22,
              height: 22,
              child: ClipOval(
                child: Image.network(
                  foto!.trim(),
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, wasSync) =>
                      frame == null && !wasSync ? iniciais : child,
                  errorBuilder: (_, _, _) => iniciais,
                ),
              ),
            )
          else
            iniciais,
          const SizedBox(width: 7),
          Text(
            'Com ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: neutral,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              holder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (propertyTitle.isNotEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.building2, size: 13, color: neutral),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              propertyTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(LucideIcons.userX, size: 13, color: neutral),
        const SizedBox(width: 6),
        Text(
          'Sem responsável',
          style: theme.textTheme.bodySmall?.copyWith(
            color: neutral,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Cadastro: quando entrou no acervo, por quem, e há quanto tempo — dado que
/// todo item tem, então a linha nunca fica vazia.
class _CadastroLine extends StatelessWidget {
  final Asset asset;
  final Color neutral;

  const _CadastroLine({required this.asset, required this.neutral});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final criado = asset.createdAt!.toLocal();
    final por = (asset.createdByName ?? '').trim();
    final partes = <String>[
      'No acervo desde ${DateFormat('dd/MM/yy', 'pt_BR').format(criado)}',
      if (por.isNotEmpty) 'por $por',
      _tempoNoAcervo(criado),
    ];
    return Row(
      children: [
        Icon(LucideIcons.archive, size: 12, color: neutral),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            partes.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: neutral,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  String _tempoNoAcervo(DateTime desde) {
    final dias = DateTime.now().difference(desde).inDays;
    if (dias <= 0) return 'hoje';
    if (dias == 1) return 'há 1 dia';
    if (dias < 30) return 'há $dias dias';
    return _idadeDoBem(desde);
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
    // Carimbo: ponto + palavra em caixa alta na cor do significado. Sem pílula
    // tingida (a casa não usa pills; a cor fica na tinta do glifo e da palavra).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.9,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

/// "há 2 a 3 m" / "há 8 m" / "este mês" — idade do bem desde a aquisição.
String _idadeDoBem(DateTime aquisicao) {
  final agora = DateTime.now();
  var meses = (agora.year - aquisicao.year) * 12 + (agora.month - aquisicao.month);
  if (agora.day < aquisicao.day) meses -= 1;
  if (meses <= 0) return 'este mês';
  final anos = meses ~/ 12;
  final resto = meses % 12;
  if (anos == 0) return 'há $meses m';
  if (resto == 0) return 'há $anos a';
  return 'há $anos a $resto m';
}
