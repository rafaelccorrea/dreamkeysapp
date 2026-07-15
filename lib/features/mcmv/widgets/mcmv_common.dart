import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../models/mcmv_models.dart';

/// Verde institucional do WhatsApp — cor por significado (o app inteiro usa
/// esse tom para a ação de WhatsApp, ex.: ClientsPage).
const Color kMcmvWhatsappGreen = Color(0xFF25D366);

/// Azul da ação "Ligar" (mesmo tom do quick contact da ClientsPage).
const Color kMcmvCallBlue = Color(0xFF3B82F6);

/// Acento da marca conforme o tema.
Color mcmvAccentColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Empresa tem o módulo MCMV? O código pode vir como `mcmv` (ModuleType do
/// backend) ou `mcmv_management` (alias) — paridade com o MODULE_ALIASES do
/// imobx-front.
bool mcmvModuleEnabled() {
  final svc = ModuleAccessService.instance;
  return McmvPermissions.moduleAliases.any(svc.hasCompanyModule);
}

/// Cor semântica do status do lead: novo = azul (informação), contactado =
/// âmbar (em andamento/atenção), qualificado = roxo (maduro), convertido =
/// verde (sucesso), perdido = neutro.
Color mcmvLeadStatusColor(BuildContext context, McmvLeadStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case McmvLeadStatus.newLead:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case McmvLeadStatus.contacted:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case McmvLeadStatus.qualified:
      return isDark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;
    case McmvLeadStatus.converted:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case McmvLeadStatus.lost:
    case McmvLeadStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData mcmvLeadStatusIcon(McmvLeadStatus status) {
  switch (status) {
    case McmvLeadStatus.newLead:
      return LucideIcons.sparkles;
    case McmvLeadStatus.contacted:
      return LucideIcons.phone;
    case McmvLeadStatus.qualified:
      return LucideIcons.userCheck;
    case McmvLeadStatus.converted:
      return LucideIcons.circleCheckBig;
    case McmvLeadStatus.lost:
      return LucideIcons.xCircle;
    case McmvLeadStatus.unknown:
      return LucideIcons.user;
  }
}

/// Cor do score (0–100): verde = quente, âmbar = morno, vermelho = frio.
Color mcmvScoreColor(BuildContext context, int score) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (score >= 70) {
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
  if (score >= 40) {
    return isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
  }
  return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
}

/// Abre `tel:`, `https://wa.me/...`, `mailto:` etc. com feedback de erro.
Future<void> mcmvLaunchUri(BuildContext context, String uri) async {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await launchUrl(parsed, mode: LaunchMode.externalApplication);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir esse link')),
    );
  }
}

String mcmvOnlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

/// Número em formato internacional para o wa.me — prefixa 55 quando o
/// telefone vier só com DDD (10–11 dígitos).
String mcmvWhatsappNumber(String phone) {
  final digits = mcmvOnlyDigits(phone);
  if (digits.length == 10 || digits.length == 11) return '55$digits';
  return digits;
}

// ─── Pílulas / chips ─────────────────────────────────────────────────────────

/// Pílula de status — tint da cor + texto na cor (nunca sólido "candy").
class McmvStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const McmvStatusPill({
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

/// Chip de filtro horizontal (linha de chips sob a busca) — mesmo DNA do
/// `_ChipChoice` do modal de filtros do Kanban.
class McmvFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;
  final int? count;

  const McmvFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg =
        selected ? accent.withValues(alpha: isDark ? 0.18 : 0.10) : fieldFill;
    final border = selected ? accent : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: selected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: selected ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count! > 99 ? '99+' : '${count!}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Cabeçalhos de painel/seção ──────────────────────────────────────────────

/// Cabeçalho de painel: glyph tonal + eyebrow com dot + título + hint (mesmo
/// DNA da tela de Comissões).
class McmvPanelHeader extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String hint;
  final Color tone;
  final Widget? trailing;

  const McmvPanelHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.hint,
    required this.tone,
    this.trailing,
  });

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
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

// ─── Estados (vazio / erro / sem acesso) ─────────────────────────────────────

class McmvEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color tone;

  const McmvEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
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
        ],
      ),
    );
  }
}

class McmvErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const McmvErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

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

/// Tela de acesso negado (sem módulo ou sem permissão).
class McmvDeniedView extends StatelessWidget {
  final String message;
  final String permission;

  const McmvDeniedView({
    super.key,
    required this.message,
    required this.permission,
  });

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
