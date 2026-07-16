// Blocos de UI compartilhados do domínio Analytics — mesma gramática das
// telas de referência (hero flush com eyebrow, abas com sublinhado, cabeçalho
// de painel com dot, cards sem borda lateral, sombras neutras).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Paleta semântica das telas de analytics — cor por SIGNIFICADO, resolvida
/// por brilho do tema.
class AnalyticsTones {
  AnalyticsTones._();

  static Color accent(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  static Color green(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  static Color amber(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  static Color blue(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.blueDarkMode
          : AppColors.status.blue;

  static Color info(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.infoDarkMode
          : AppColors.status.info;

  static Color purple(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

  static Color red(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;

  /// Verde/âmbar/vermelho por faixa de score 0–100 (cor com significado).
  static Color byScore(BuildContext c, double score) {
    if (score >= 80) return green(c);
    if (score >= 60) return amber(c);
    return red(c);
  }

  /// Tom por nível de risco (`high`/`medium`/`low`).
  static Color byRisk(BuildContext c, String riskLevel) {
    switch (riskLevel) {
      case 'high':
        return red(c);
      case 'medium':
        return amber(c);
      default:
        return green(c);
    }
  }
}

/// Dados de um bloco do KPI strip do hero.
class HeroKpiData {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color tone;

  const HeroKpiData({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.tone,
  });
}

/// Strip de KPIs do hero — blocos separados por filete vertical, valor na cor
/// semântica e régua de 18px embaixo (DNA das Comissões/Aprovações).
class HeroKpiStrip extends StatelessWidget {
  const HeroKpiStrip({super.key, required this.blocks, this.loading = false});

  final List<HeroKpiData> blocks;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: _block(context, blocks[i])),
          ],
        ],
      ),
    );
  }

  Widget _block(BuildContext context, HeroKpiData data) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: 11, color: data.tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: data.tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              loading ? '—' : data.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: data.tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            data.sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: data.tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eyebrow do hero: dot com glow + rótulo tracking-wide na cor da marca.
class HeroEyebrow extends StatelessWidget {
  const HeroEyebrow({super.key, required this.label, required this.dotColor});

  final String label;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.55),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AnalyticsTones.accent(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// Título grande do hero: número + complemento na base.
class HeroHeadline extends StatelessWidget {
  const HeroHeadline({
    super.key,
    required this.value,
    required this.suffix,
    required this.subtitle,
  });

  final String value;
  final String suffix;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.0,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                suffix,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Aba flush com sublinhado (não pill) — ícone + rótulo + contagem opcional.
class AnalyticsFlushTab extends StatelessWidget {
  const AnalyticsFlushTab({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

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
                    if (count != null && count! > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color:
                              tone.withValues(alpha: selected ? 0.18 : 0.12),
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

/// Cabeçalho de painel: chip de ícone + eyebrow com dot + título + hint.
class AnalyticsPanelHeader extends StatelessWidget {
  const AnalyticsPanelHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.hint,
    required this.tone,
    this.trailing,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String hint;
  final Color tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Cabeçalho de sub-seção: ícone + rótulo MAIÚSCULO + contagem + filete.
class AnalyticsSubsectionHeader extends StatelessWidget {
  const AnalyticsSubsectionHeader({
    super.key,
    required this.label,
    required this.icon,
    this.count,
  });

  final String label;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${count!}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Card de métrica — sem borda lateral, sombra neutra, ícone tintado.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                child: Icon(icon, size: 16, color: tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 9.5,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 5),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grid responsivo de [MetricCard] (2 colunas; 3 quando largo).
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? 3 : 2;
        const gap = 10.0;
        final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: w, child: card),
          ],
        );
      },
    );
  }
}

/// Pill pequena de status/valor (ação no próprio item).
class MiniPill extends StatelessWidget {
  const MiniPill({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.28)),
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
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio com círculo tintado (DNA das Comissões).
class AnalyticsEmptyState extends StatelessWidget {
  const AnalyticsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
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
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de erro com retry.
class AnalyticsErrorState extends StatelessWidget {
  const AnalyticsErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AnalyticsTones.red(context);
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

/// Tela de acesso negado (permissão faltante) — padrão das Comissões.
class AnalyticsDeniedView extends StatelessWidget {
  const AnalyticsDeniedView({
    super.key,
    required this.message,
    required this.permission,
  });

  final String message;
  final String permission;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão "$permission".',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
