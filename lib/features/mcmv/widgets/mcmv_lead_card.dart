import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/mcmv_models.dart';
import 'mcmv_common.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 0,
);

/// Item da lista de leads MCMV — linha flush (sem card/sombra) no mesmo DNA da
/// CommissionCard: glyph tonal com iniciais, pílulas de status/faixa/
/// elegibilidade, localização + renda, e ações de contato **no próprio item**
/// (WhatsApp / Ligar). Score em destaque à direita.
class McmvLeadCard extends StatelessWidget {
  final McmvLead lead;
  final VoidCallback? onTap;

  const McmvLeadCard({super.key, required this.lead, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = mcmvLeadStatusColor(context, lead.status);
    final scoreTone = mcmvScoreColor(context, lead.score);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final location = lead.locationLabel;
    final dateLabel = lead.createdAt == null
        ? null
        : DateFormat('dd/MM/yy', 'pt_BR').format(lead.createdAt!.toLocal());

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Glyph tonal com iniciais do lead.
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                      border: Border.all(color: tone.withValues(alpha: 0.28)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(lead.name),
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            McmvStatusPill(
                              label: lead.status.label,
                              color: tone,
                            ),
                            McmvStatusPill(
                              label: lead.incomeRange.label,
                              color: neutral,
                            ),
                            McmvStatusPill(
                              label:
                                  lead.eligible ? 'Elegível' : 'Não elegível',
                              color: lead.eligible ? emerald : danger,
                              icon: lead.eligible
                                  ? LucideIcons.check
                                  : LucideIcons.x,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lead.name.trim().isEmpty
                              ? 'Lead sem nome'
                              : lead.name.trim(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(LucideIcons.mapPin,
                                  size: 12, color: neutral),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
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
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 3,
                          children: [
                            if (lead.monthlyIncome > 0)
                              _SpecBit(
                                icon: LucideIcons.wallet,
                                text:
                                    'Renda ${_money.format(lead.monthlyIncome)}',
                                color: neutral,
                              ),
                            if (lead.familySize > 0)
                              _SpecBit(
                                icon: LucideIcons.users,
                                text: '${lead.familySize} '
                                    'pessoa${lead.familySize == 1 ? '' : 's'}',
                                color: neutral,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Score + data de criação.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${lead.score}%',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scoreTone,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'SCORE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w900,
                          fontSize: 8.5,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (dateLabel != null)
                        Text(
                          dateLabel,
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
              const SizedBox(height: 10),
              _buildContactRow(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Ações de contato no próprio item (não escondidas em menu): WhatsApp e
  /// Ligar, com rating à direita quando existir.
  Widget _buildContactRow(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final border = ThemeHelpers.borderLightColor(context);
    final phone = lead.phone.trim();

    final actions = <Widget>[];
    if (phone.isNotEmpty) {
      actions.add(_QuickContact(
        icon: LucideIcons.messageCircle,
        label: 'WhatsApp',
        color: kMcmvWhatsappGreen,
        onTap: () => mcmvLaunchUri(
          context,
          'https://wa.me/${mcmvWhatsappNumber(phone)}',
        ),
      ));
      actions.add(_QuickContact(
        icon: LucideIcons.phone,
        label: 'Ligar',
        color: kMcmvCallBlue,
        onTap: () => mcmvLaunchUri(context, 'tel:${mcmvOnlyDigits(phone)}'),
      ));
    }
    if (lead.email.trim().isNotEmpty) {
      actions.add(_QuickContact(
        icon: LucideIcons.mail,
        label: 'Email',
        color: amber,
        onTap: () => mcmvLaunchUri(context, 'mailto:${lead.email.trim()}'),
      ));
    }

    if (actions.isEmpty && lead.rating == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.025),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: border,
              ),
            actions[i],
          ],
          const Spacer(),
          if (lead.rating != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.star, size: 13, color: amber),
                const SizedBox(width: 3),
                Text(
                  '${lead.rating}/5',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: neutral,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Botão compacto de contato dentro do item.
class _QuickContact extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickContact({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
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

  const _SpecBit({
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
