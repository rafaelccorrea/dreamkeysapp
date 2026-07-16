import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Tons semânticos compartilhados pelas telas de Condomínios/Empreendimentos.
class EstateTones {
  EstateTones._();

  static Color brand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  static Color green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  static Color amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  static Color blue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.blueDarkMode
          : AppColors.status.blue;

  static Color purple(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

  static Color danger(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;
}

/// Aba flush (sublinhado, sem pills) — mesma gramática das Comissões.
class EstateFlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const EstateFlushTab({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count! > 99 ? '99+' : '${count!}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? tone
                                : ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eyebrow de seção flush: dot com glow + rótulo em caps + hint opcional.
class EstateSectionHeader extends StatelessWidget {
  final Color tone;
  final String label;
  final String? hint;

  const EstateSectionHeader({
    super.key,
    required this.tone,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: tone.withValues(alpha: 0.45), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: ThemeHelpers.textSecondaryColor(context)
                  .withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pill pequena (status/meta) usada em cards e sheets.
class EstateMiniPill extends StatelessWidget {
  final String label;
  final Color tone;
  final IconData? icon;

  const EstateMiniPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio (com variação para busca sem resultado).
class EstateEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color tone;
  final Widget? action;

  const EstateEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Estado de erro com retry.
class EstateErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const EstateErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = EstateTones.danger(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

/// Skeleton fiel ao [EstateCard] (row CRM): thumbnail 92×92 + coluna densa
/// com pills, tipo, nome, endereço, specs e linha-âncora.
class EstateCardSkeleton extends StatelessWidget {
  const EstateCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? Colors.white.withValues(alpha: 0.025) : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 92, height: 92, borderRadius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    SkeletonBox(width: 62, height: 20, borderRadius: 999),
                    Spacer(),
                    SkeletonBox(width: 40, height: 28, borderRadius: 12),
                  ],
                ),
                const SizedBox(height: 8),
                const SkeletonText(width: 110, height: 11, borderRadius: 4),
                const SizedBox(height: 7),
                const SkeletonText(width: 180, height: 14, borderRadius: 5),
                const SizedBox(height: 7),
                const SkeletonText(width: 150, height: 11, borderRadius: 4),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    SkeletonText(width: 90, height: 15, borderRadius: 5),
                    Spacer(),
                    SkeletonBox(width: 72, height: 20, borderRadius: 999),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// KPI fluido e CLICÁVEL do hero — mesma gramática das métricas da tela de
/// Imóveis: ícone tinted compacto + label uppercase + número grande (w900)
/// + traço gradient na cor da categoria. Sem caixa/borda/sombra; o toque
/// seleciona o escopo correspondente (sublinhado pelas abas).
class EstateStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const EstateStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final mutedColor = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accent.withValues(
                          alpha: selected
                              ? (isDark ? 0.26 : 0.18)
                              : (isDark ? 0.16 : 0.12)),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: accent.withValues(
                            alpha: selected
                                ? (isDark ? 0.5 : 0.38)
                                : (isDark ? 0.32 : 0.22)),
                      ),
                    ),
                    child: Icon(icon, color: accent, size: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected ? accent : mutedColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.05,
                    color: textColor,
                    fontSize: 24,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: 2,
                width: selected ? 40 : 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(
                          alpha: selected ? 1 : (isDark ? 0.85 : 0.7)),
                      accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha rótulo → valor usada em sheets/detalhe.
class EstateInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const EstateInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formata CNPJ (14 dígitos) — paridade com o web.
String formatCnpjPretty(String? cnpj) {
  if (cnpj == null || cnpj.trim().isEmpty) return '';
  final digits = cnpj.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 14) return cnpj;
  return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.'
      '${digits.substring(5, 8)}/${digits.substring(8, 12)}-'
      '${digits.substring(12)}';
}

/// Host limpo de um website (sem protocolo/`www.`).
String websiteHost(String? website) {
  final raw = (website ?? '').trim();
  if (raw.isEmpty) return '';
  try {
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    return Uri.parse(url).host.replaceFirst(RegExp(r'^www\.'), '');
  } catch (_) {
    return raw;
  }
}
