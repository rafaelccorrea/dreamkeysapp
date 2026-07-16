import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/shimmer_image.dart';
import 'estate_shared.dart';

/// Pill informativa do card (rodapé/linha de status).
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

/// Par (ícone, rótulo) da linha de specs — mesma gramática dos specs de
/// quartos/banheiros/área do card de imóvel.
class EstateSpecBit {
  final IconData icon;
  final String label;

  const EstateSpecBit({required this.icon, required this.label});
}

/// Card de condomínio/empreendimento na gramática do **row CRM da tela de
/// Imóveis**: thumbnail 92×92 à esquerda + coluna densa à direita com
/// status, tipo, nome forte, endereço como spec, bits informativos e a
/// cidade como linha-âncora. Ações no próprio item via kebab (e long-press).
class EstateCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int photoCount;
  final bool isActive;
  final IconData typeIcon;
  final String typeLabel;
  final bool hasCnpj;
  final String addressLine;
  final String cityLine;
  final List<EstateSpecBit> specs;
  final EstateCardChip? footerPill;
  final IconData fallbackIcon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  const EstateCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.photoCount,
    required this.isActive,
    required this.typeIcon,
    required this.typeLabel,
    this.hasCnpj = false,
    required this.addressLine,
    required this.cityLine,
    this.specs = const [],
    this.footerPill,
    required this.fallbackIcon,
    required this.accent,
    required this.onTap,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final borderColor = ThemeHelpers.borderColor(context);
    final statusTone =
        isActive ? EstateTones.green(context) : EstateTones.amber(context);
    final cardBg =
        isDark ? Colors.white.withValues(alpha: 0.025) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onMenu == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onMenu!();
              },
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.05),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EstateRowThumbnail(
                  imageUrl: imageUrl,
                  photoCount: photoCount,
                  fallbackIcon: fallbackIcon,
                  accent: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // L1: status/situação + kebab no canto direito.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                EstateMiniPill(
                                  label: isActive ? 'Ativo' : 'Inativo',
                                  icon: isActive
                                      ? LucideIcons.circleCheckBig
                                      : LucideIcons.circleOff,
                                  tone: statusTone,
                                ),
                              ],
                            ),
                          ),
                          if (onMenu != null) _kebabButton(context),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // L2: chip CNPJ + tipo do cadastro.
                      Row(
                        children: [
                          if (hasCnpj) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: secondary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: secondary.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.landmark,
                                      size: 9, color: secondary),
                                  const SizedBox(width: 3),
                                  Text(
                                    'CNPJ',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: secondary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Icon(typeIcon, size: 12, color: secondary),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: -0.05,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // L3: nome (1 linha, forte).
                      Text(
                        name.isEmpty ? 'Sem nome' : name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.25,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // L4: endereço como spec.
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 11, color: secondary),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              addressLine.trim().isEmpty
                                  ? 'Endereço não informado'
                                  : addressLine,
                              style: TextStyle(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // L5: bits informativos (fotos/links/arquivos/CEP…).
                      if (specs.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 3,
                          children: [
                            for (final s in specs)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    s.icon,
                                    size: 12,
                                    color: textColor.withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    s.label,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // L6: cidade como linha-âncora + pill de rodapé.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              cityLine.trim().isEmpty
                                  ? 'Cidade não informada'
                                  : cityLine,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                fontSize: 15.5,
                                height: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (footerPill != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: footerPill!
                                    .tone(context)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: footerPill!
                                      .tone(context)
                                      .withValues(alpha: 0.32),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    footerPill!.icon,
                                    size: 11,
                                    color: footerPill!.tone(context),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    footerPill!.label,
                                    style: TextStyle(
                                      color: footerPill!.tone(context),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10.5,
                                      letterSpacing: 0.2,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
      ),
    );
  }

  /// Kebab escuro no canto do item — mesma pegada do card de imóvel.
  Widget _kebabButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onMenu!();
        },
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: 'Opções',
          child: Container(
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// Thumbnail 92×92 do row — borda fina, contador de fotos em overlay e
/// fallback gracioso na cor da tela quando não há imagem.
class _EstateRowThumbnail extends StatelessWidget {
  const _EstateRowThumbnail({
    required this.imageUrl,
    required this.photoCount,
    required this.fallbackIcon,
    required this.accent,
  });

  final String? imageUrl;
  final int photoCount;
  final IconData fallbackIcon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final borderColor = ThemeHelpers.borderColor(context);
    final hasMain = (imageUrl ?? '').trim().isNotEmpty;

    return SizedBox(
      width: 92,
      height: 92,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor.withValues(alpha: 0.5)),
              ),
              child: hasMain
                  ? ShimmerImage(
                      imageUrl: imageUrl!,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorWidget: _fallback(context),
                    )
                  : _fallback(context),
            ),
            if (photoCount > 1)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 9,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$photoCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 9.5,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.22 : 0.12),
            accent.withValues(alpha: isDark ? 0.07 : 0.04),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            fallbackIcon,
            size: 20,
            color: accent.withValues(alpha: isDark ? 0.85 : 0.75),
          ),
        ),
      ),
    );
  }
}

/// Ação do sheet de ações rápidas do item.
class EstateQuickAction {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool destructive;
  final VoidCallback onTap;

  const EstateQuickAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.destructive = false,
    required this.onTap,
  });
}

/// Sheet de ações rápidas do item — mesma gramática do menu contextual do
/// card de imóvel: atracado no rodapé, header editorial (eyebrow + título +
/// meta de localização) e tiles fluidas com cor por intenção.
class EstateQuickActionsSheet extends StatelessWidget {
  final Color accent;
  final String title;
  final String meta;
  final List<EstateQuickAction> actions;

  const EstateQuickActionsSheet({
    super.key,
    required this.accent,
    required this.title,
    required this.meta,
    required this.actions,
  });

  static Future<void> show(
    BuildContext context, {
    required Color accent,
    required String title,
    required String meta,
    required List<EstateQuickAction> actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => EstateQuickActionsSheet(
        accent: accent,
        title: title,
        meta: meta,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.32),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 14, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AÇÕES RÁPIDAS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: ThemeHelpers.textColor(context),
                                height: 1.15,
                                fontSize: 19,
                              ),
                            ),
                            if (meta.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: ThemeHelpers.textSecondaryColor(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ThemeHelpers.borderColor(context),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final a in actions) _tile(context, a),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, EstateQuickAction a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          a.onTap();
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: a.color.withValues(alpha: 0.16),
        highlightColor: a.color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: a.color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: a.color.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(a.icon, size: 19, color: a.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: a.destructive
                            ? a.color
                            : ThemeHelpers.textColor(context),
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: muted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
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
}
