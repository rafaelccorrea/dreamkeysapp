import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/automation_models.dart';

/// Cor semântica da categoria — paleta variada nas secundárias (violet/emerald/
/// sky/amber), nunca arco-íris candy: sempre tints discretos sobre o item.
Color automationCategoryColor(
  BuildContext context,
  AutomationCategory category,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (category) {
    case AutomationCategory.process:
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    case AutomationCategory.financial:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case AutomationCategory.rental:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case AutomationCategory.crm:
      return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    case AutomationCategory.marketing:
      return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    case AutomationCategory.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Ícone do gatilho — mapeia o `icon` textual do backend (checklist, payment,
/// contract, followup, match, subscription, inspection, appointment, expense)
/// com fallback pelo tipo.
IconData automationIcon(String icon, String type) {
  switch (icon) {
    case 'checklist':
      return LucideIcons.listChecks;
    case 'payment':
      return LucideIcons.wallet;
    case 'contract':
      return LucideIcons.fileText;
    case 'followup':
      return LucideIcons.userCheck;
    case 'match':
      return LucideIcons.heartHandshake;
    case 'subscription':
      return LucideIcons.creditCard;
    case 'inspection':
      return LucideIcons.clipboardCheck;
    case 'appointment':
      return LucideIcons.calendarClock;
    case 'expense':
      return LucideIcons.receipt;
  }
  if (type.startsWith('checklist')) return LucideIcons.listChecks;
  if (type.startsWith('payment')) return LucideIcons.wallet;
  if (type.startsWith('contract')) return LucideIcons.fileText;
  if (type.contains('followup')) return LucideIcons.userCheck;
  if (type.contains('match')) return LucideIcons.heartHandshake;
  if (type.startsWith('subscription')) return LucideIcons.creditCard;
  if (type.startsWith('inspection')) return LucideIcons.clipboardCheck;
  if (type.startsWith('appointment')) return LucideIcons.calendarClock;
  if (type.startsWith('expense')) return LucideIcons.receipt;
  return LucideIcons.zap;
}

/// Cor semântica do status de execução (verde = ok, âmbar = parcial,
/// vermelho = erro).
Color executionStatusColor(
  BuildContext context,
  AutomationExecutionStatus status,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case AutomationExecutionStatus.success:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case AutomationExecutionStatus.partial:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case AutomationExecutionStatus.error:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case AutomationExecutionStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData executionStatusIcon(AutomationExecutionStatus status) {
  switch (status) {
    case AutomationExecutionStatus.success:
      return LucideIcons.circleCheck;
    case AutomationExecutionStatus.partial:
      return LucideIcons.circleAlert;
    case AutomationExecutionStatus.error:
      return LucideIcons.circleX;
    case AutomationExecutionStatus.unknown:
      return LucideIcons.circleHelp;
  }
}

/// Rótulo relativo da última execução (EXATO do web — `formatDate`).
String automationLastRunLabel(DateTime? date) {
  if (date == null) return 'Nunca';
  final now = DateTime.now();
  final diffDays = now.difference(date.toLocal()).inDays;
  if (diffDays == 0) return 'Hoje';
  if (diffDays == 1) return 'Ontem';
  if (diffDays < 7) return '$diffDays dias atrás';
  return DateFormat('dd/MM/yyyy', 'pt_BR').format(date.toLocal());
}

/// Pílula tint (fundo translúcido + borda + texto na cor) — padrão do app.
class AutomationPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AutomationPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
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
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
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

/// Mini-metadado (ícone + texto compacto) — execuções, sucessos, erros.
class AutomationSpecBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const AutomationSpecBit({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

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

/// Item da lista de automações — **linha flush** (sem card/sombra), coerente
/// com o DNA do app: glyph tonal da categoria, info no meio e o toggle de
/// ativar/desativar NO PRÓPRIO ITEM (ação principal do web). Toca para abrir
/// a configuração.
class AutomationCard extends StatelessWidget {
  final Automation automation;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  /// Trava o switch enquanto o PATCH está em voo.
  final bool toggling;

  const AutomationCard({
    super.key,
    required this.automation,
    this.onTap,
    this.onToggle,
    this.toggling = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = automationCategoryColor(context, automation.category);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    // Inativa fica "apagada" — informação pela opacidade, não por cinza chapado.
    final active = automation.isActive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
              Opacity(
                opacity: active ? 1 : 0.55,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                    border: Border.all(color: tone.withValues(alpha: 0.28)),
                  ),
                  child: Icon(
                    automationIcon(automation.icon, automation.type),
                    color: tone,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: active ? 1 : 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: AutomationPill(
                              label: automation.category.label,
                              color: tone,
                            ),
                          ),
                          if (automation.hasFailures) ...[
                            const SizedBox(width: 6),
                            Icon(LucideIcons.triangleAlert,
                                size: 13, color: danger),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              active ? 'Ativa' : 'Inativa',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: active ? green : neutral,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        automation.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (automation.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          automation.description.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AutomationSpecBit(
                            icon: LucideIcons.activity,
                            text: '${automation.executionCount} '
                                'execuç${automation.executionCount == 1 ? 'ão' : 'ões'}',
                            color: neutral,
                          ),
                          if (automation.successfulExecutions > 0)
                            AutomationSpecBit(
                              icon: LucideIcons.circleCheck,
                              text: '${automation.successfulExecutions}',
                              color: green,
                            ),
                          if (automation.failedExecutions > 0)
                            AutomationSpecBit(
                              icon: LucideIcons.circleX,
                              text: '${automation.failedExecutions}',
                              color: danger,
                            ),
                          AutomationSpecBit(
                            icon: LucideIcons.clock,
                            text: automationLastRunLabel(
                                automation.lastExecutionAt),
                            color: neutral,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Ação no próprio item: ativar/desativar.
              Column(
                children: [
                  const SizedBox(height: 4),
                  toggling
                      ? SizedBox(
                          width: 40,
                          height: 24,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accent,
                              ),
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 24,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Switch.adaptive(
                              value: active,
                              activeTrackColor: green,
                              onChanged:
                                  onToggle == null ? null : (v) => onToggle!(v),
                            ),
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
