import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/subscription_models.dart';

/// Cor SEMÂNTICA do status de assinatura — verde = ativa, âmbar = suspensa /
/// pendente, vermelho = expirada / cancelada, violeta = plano personalizado /
/// conta gerenciada, cinza = inativa.
Color subscriptionStatusColor(BuildContext context, String status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status.toLowerCase().trim()) {
    case 'active':
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case 'suspended':
    case 'pending':
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case 'expired':
    case 'cancelled':
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case 'managed_exempt':
    case 'custom_plan':
      return isDark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;
    default:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Ícone do tipo de plano (basic → camadas, professional → joia, custom →
/// ajustes) — paridade com `PlanCategoryIcon` do web.
IconData planTypeIcon(String type) {
  switch (type.toLowerCase().trim()) {
    case 'basic':
      return LucideIcons.layers;
    case 'professional':
    case 'pro':
      return LucideIcons.gem;
    case 'custom':
      return LucideIcons.settings2;
    default:
      return LucideIcons.sparkles;
  }
}

/// Rótulo pt-BR do tipo de plano.
String planTypeLabel(String type) {
  switch (type.toLowerCase().trim()) {
    case 'basic':
      return 'Básico';
    case 'professional':
    case 'pro':
      return 'Profissional';
    case 'custom':
      return 'Personalizado';
    default:
      return type.isEmpty ? '—' : type;
  }
}

// ─── Pill de status ───────────────────────────────────────────────────────────

class SubsStatusPill extends StatelessWidget {
  const SubsStatusPill({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = subscriptionStatusColor(context, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.42 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            subscriptionStatusLabel(status),
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10.5 : 11.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Aba flush (sublinhado — mesma gramática das telas de referência) ────────

class SubsFlushTab extends StatelessWidget {
  const SubsFlushTab({
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
  final int? count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

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
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count! > 99 ? '99+' : '$count',
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

// ─── Cabeçalho de painel (eyebrow + dot + título + hint) ─────────────────────

class SubsPanelHeader extends StatelessWidget {
  const SubsPanelHeader({
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
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
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

// ─── Medidor de uso (recurso: usado / limite + barra) ────────────────────────

class UsageMeterTile extends StatelessWidget {
  const UsageMeterTile({
    super.key,
    required this.icon,
    required this.label,
    required this.metric,
    this.unit,
  });

  final IconData icon;
  final String label;
  final UsageMetric metric;

  /// Sufixo do valor (ex.: 'GB'). Nulo = contagem simples.
  final String? unit;

  Color _tone(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (metric.isOverLimit) {
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
    if (metric.isNearLimit) {
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    }
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _tone(context);
    final unlimited = metric.isUnlimited;
    final suffix = unit == null ? '' : ' $unit';
    final usedLabel = '${_fmt(metric.used)}$suffix';
    final limitLabel =
        unlimited ? 'Ilimitado' : 'de ${_fmt(metric.limit)}$suffix';
    final pct = unlimited
        ? 0.0
        : (metric.percentage / 100).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: usedLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            unlimited ? ThemeHelpers.textColor(context) : tone,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: '  $limitLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (unlimited)
            Row(
              children: [
                Icon(LucideIcons.infinity, size: 13, color: secondary),
                const SizedBox(width: 6),
                Text(
                  'Sem limite neste plano',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(
                      color: ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: 0.8),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct == 0 && metric.used > 0 ? 0.02 : pct,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [tone, tone.withValues(alpha: 0.75)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Linha label/valor ────────────────────────────────────────────────────────

class SubsInfoRow extends StatelessWidget {
  const SubsInfoRow({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.valueWidget,
    this.emphasize = false,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final Widget? valueWidget;
  final bool emphasize;

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
          if (valueWidget != null)
            Flexible(child: valueWidget!)
          else
            Flexible(
              child: Text(
                value ?? '—',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Divisor fino ─────────────────────────────────────────────────────────────

class SubsDivider extends StatelessWidget {
  const SubsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
      ),
    );
  }
}

// ─── Estados vazio / erro / acesso negado ─────────────────────────────────────

class SubsEmptyState extends StatelessWidget {
  const SubsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tone;
  final Widget? action;

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
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class SubsErrorState extends StatelessWidget {
  const SubsErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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

/// Acesso negado (gate por papel) — mesma linguagem do restante do app:
/// travar mostrando o motivo, sem expor chave técnica.
class SubsDeniedView extends StatelessWidget {
  const SubsDeniedView({super.key, required this.message});

  final String message;

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
              'Fale com um administrador da sua imobiliária.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
