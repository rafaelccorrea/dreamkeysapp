import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/property_settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Peças visuais das telas de Configuração de imóveis (hub + 4 telas).
// Cards com borda suave, roundels coloridos, chips e seções com título —
// tudo por ThemeHelpers/AppColors, claro e escuro.
// ═══════════════════════════════════════════════════════════════════════════

bool psDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Paleta das telas (cada tela tem a sua tinta no hub e no cabeçalho).
class PsPalette {
  PsPalette._();

  static Color indigo(BuildContext c) =>
      psDark(c) ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
  static Color teal(BuildContext c) => psDark(c)
      ? AppColors.status.tealDarkMode
      : AppColors.status.teal;
  static Color amber(BuildContext c) =>
      psDark(c) ? const Color(0xFFE6B84C) : const Color(0xFFD97706);
  static Color green(BuildContext c) => psDark(c)
      ? AppColors.status.successDarkMode
      : AppColors.status.success;
  static Color red(BuildContext c) =>
      psDark(c) ? AppColors.status.errorDarkMode : AppColors.status.error;
  static Color primary(BuildContext c) => psDark(c)
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
  static Color purple(BuildContext c) => psDark(c)
      ? AppColors.status.purpleDarkMode
      : AppColors.status.purple;
  static Color blue(BuildContext c) =>
      psDark(c) ? AppColors.status.infoDarkMode : AppColors.status.info;

  /// Cor do papel (lista "Dados do proprietário").
  static Color role(BuildContext c, OwnerDataRole r) => switch (r) {
        OwnerDataRole.master => red(c),
        OwnerDataRole.admin => purple(c),
        OwnerDataRole.manager => blue(c),
        OwnerDataRole.user => teal(c),
      };

  /// `#RRGGBB` → Color (cor da equipe); inválido → ardósia.
  static Color hex(String? raw) {
    var t = (raw ?? '').trim().replaceFirst('#', '');
    if (t.length == 3) t = t.split('').map((ch) => '$ch$ch').join();
    final v = int.tryParse(t, radix: 16);
    if (t.length != 6 || v == null) return const Color(0xFF64748B);
    return Color(0xFF000000 | v);
  }
}

/// Feedback curto (verde = deu certo, vermelho = falhou, âmbar = aviso).
void psSnack(BuildContext context, String message,
    {bool ok = false, bool warn = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
        backgroundColor: warn
            ? const Color(0xFFB45309)
            : (ok ? AppColors.status.success : AppColors.status.error),
      ),
    );
}

/// Mensagem de falha: a do servidor quando houver, senão a de reserva.
String psFailMessage(String? serverMessage, String fallback) {
  final t = (serverMessage ?? '').trim();
  return t.isEmpty ? fallback : t;
}

/// Confirmação (destrutiva em vermelho).
Future<bool> psConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final tone = destructive ? PsPalette.red(context) : PsPalette.primary(context);
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: ThemeHelpers.textColor(ctx),
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          height: 1.45,
          color: ThemeHelpers.textSecondaryColor(ctx),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: tone),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Círculo/quadrado arredondado com ícone colorido.
class PsRoundel extends StatelessWidget {
  const PsRoundel({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.25)!],
              )
            : null,
        color: filled ? null : color.withValues(alpha: dark ? 0.2 : 0.11),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: dark ? 0.35 : 0.22)),
      ),
      child: Icon(
        icon,
        size: iconSize ?? size * 0.48,
        color: filled ? Colors.white : color,
      ),
    );
  }
}

/// Chip de leitura ("12 obrigatórios", "Votação ●").
class PsChip extends StatelessWidget {
  const PsChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.value,
    this.on = true,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? value;

  /// Desligado = cinza (a regra não vale).
  final bool on;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = on ? color : muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: on ? (dark ? 0.18 : 0.09) : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: on ? 0.38 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
          ],
          if (value != null) ...[
            Text(
              value!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: on ? ThemeHelpers.textColor(context) : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho das telas: cartão com degradê na tinta da tela, roundel,
/// eyebrow em caixa alta, título, frase e chips de leitura.
class PsHero extends StatelessWidget {
  const PsHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
    this.chips = const <Widget>[],
    this.footer,
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final List<Widget> chips;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final card = ThemeHelpers.cardBackgroundColor(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(color.withValues(alpha: dark ? 0.22 : 0.10), card),
            card,
          ],
        ),
        border: Border.all(color: color.withValues(alpha: dark ? 0.32 : 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: dark ? 0.10 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PsRoundel(icon: icon, color: color, size: 48, filled: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: ThemeHelpers.textColor(context),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// Seção em cartão: roundel + título + subtítulo + ação à direita.
class PsSection extends StatelessWidget {
  const PsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeHelpers.shadowColor(context).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PsRoundel(icon: icon, color: color, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      if ((subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Linha de regra com interruptor (cartão interno).
class PsSwitchTile extends StatelessWidget {
  const PsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final tone = color ?? PsPalette.green(context);
    final border = value
        ? tone.withValues(alpha: dark ? 0.45 : 0.35)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.7);
    return Material(
      color: value
          ? tone.withValues(alpha: dark ? 0.10 : 0.05)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                PsRoundel(
                  icon: icon!,
                  color: value ? tone : ThemeHelpers.textSecondaryColor(context),
                  size: 32,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    if ((subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.2,
                          height: 1.35,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: tone,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nota/aviso com faixa colorida.
class PsNote extends StatelessWidget {
  const PsNote({
    super.key,
    required this.text,
    this.icon = LucideIcons.info,
    this.color,
  });

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final tone = color ?? PsPalette.blue(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: dark ? 0.35 : 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar com foto ou iniciais.
class PsAvatar extends StatelessWidget {
  const PsAvatar({
    super.key,
    required this.name,
    required this.color,
    this.url,
    this.size = 36,
  });

  final String name;
  final String? url;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final initials = Text(
      propertySettingsInitials(name),
      style: TextStyle(
        fontSize: size * 0.34,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
      ),
      child: (url ?? '').isEmpty
          ? initials
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initials,
            ),
    );
  }
}

/// Selo pequeno em caixa alta ("OBRIGATÓRIO", "SISTEMA").
class PsBadge extends StatelessWidget {
  const PsBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Esqueleto de carregamento (blocos suaves).
class PsSkeleton extends StatelessWidget {
  const PsSkeleton({super.key, this.blocks = const [120, 220, 180]});

  final List<double> blocks;

  @override
  Widget build(BuildContext context) {
    final base = ThemeHelpers.borderColor(context).withValues(alpha: 0.35);
    return Column(
      children: [
        for (final h in blocks)
          Container(
            height: h,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    );
  }
}

/// Estado vazio dentro de uma seção.
class PsEmpty extends StatelessWidget {
  const PsEmpty({super.key, required this.text, this.icon = LucideIcons.inbox});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
        ),
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: muted),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Barra fixa de salvar (aparece quando há alteração).
class PsSaveBar extends StatelessWidget {
  const PsSaveBar({
    super.key,
    required this.changes,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
    required this.color,
    this.blockReason,
    this.saveLabel = 'Salvar',
  });

  final int changes;
  final bool saving;
  final String? blockReason;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final Color color;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final amber = PsPalette.amber(context);
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: ThemeHelpers.borderColor(context)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      changes == 1
                          ? '1 alteração não salva'
                          : '$changes alterações não salvas',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    if (blockReason != null)
                      Text(
                        blockReason!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: amber),
                      )
                    else
                      Text(
                        'Salve para valer em todo o cadastro.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: saving ? null : onDiscard,
                child: const Text('Descartar'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (saving || blockReason != null) ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.save, size: 16),
                label: Text(saving ? 'Salvando…' : saveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultado do seletor de usuário.
class PsUserPick {
  const PsUserPick(this.member, {this.flag = false});
  final PropertySettingsMember? member;

  /// O interruptor opcional do seletor (ex.: "obrigatório").
  final bool flag;
}

/// Folha de baixo para escolher um membro da empresa, com busca. Com
/// [allowNone], a 1ª opção é "nenhum" (devolve `PsUserPick(null)`).
Future<PsUserPick?> showPsUserPicker(
  BuildContext context, {
  required String title,
  required List<PropertySettingsMember> users,
  Set<String> excludeIds = const <String>{},
  String? subtitle,
  String? selectedId,
  String? noneLabel,
  String? flagLabel,
  String? flagHint,
  String emptyText = 'Nenhum usuário ativo para escolher.',
  required Color color,
}) {
  return showModalBottomSheet<PsUserPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _PsUserPickerSheet(
      title: title,
      subtitle: subtitle,
      users: users.where((u) => !excludeIds.contains(u.id)).toList(),
      totalUsers: users.length,
      selectedId: selectedId,
      noneLabel: noneLabel,
      flagLabel: flagLabel,
      flagHint: flagHint,
      emptyText: emptyText,
      color: color,
    ),
  );
}

class _PsUserPickerSheet extends StatefulWidget {
  const _PsUserPickerSheet({
    required this.title,
    required this.users,
    required this.totalUsers,
    required this.emptyText,
    required this.color,
    this.subtitle,
    this.selectedId,
    this.noneLabel,
    this.flagLabel,
    this.flagHint,
  });

  final String title;
  final String? subtitle;
  final List<PropertySettingsMember> users;
  final int totalUsers;
  final String? selectedId;
  final String? noneLabel;
  final String? flagLabel;
  final String? flagHint;
  final String emptyText;
  final Color color;

  @override
  State<_PsUserPickerSheet> createState() => _PsUserPickerSheetState();
}

class _PsUserPickerSheetState extends State<_PsUserPickerSheet> {
  String _query = '';
  bool _flag = false;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final list = OwnerDataRules.filter(widget.users, _query);
    final height = MediaQuery.of(context).size.height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            if ((widget.subtitle ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  hintText: 'Buscar por nome ou e-mail',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (widget.flagLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: PsSwitchTile(
                  title: widget.flagLabel!,
                  subtitle: widget.flagHint,
                  value: _flag,
                  icon: LucideIcons.star,
                  color: PsPalette.amber(context),
                  onChanged: (v) => setState(() => _flag = v),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  if (widget.noneLabel != null)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: PsRoundel(
                        icon: LucideIcons.userX,
                        color: muted,
                        size: 36,
                      ),
                      title: Text(
                        widget.noneLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: (widget.selectedId ?? '').isEmpty
                          ? Icon(LucideIcons.check, color: widget.color)
                          : null,
                      onTap: () =>
                          Navigator.of(context).pop(const PsUserPick(null)),
                    ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: PsEmpty(
                        text: widget.users.isEmpty
                            ? (widget.totalUsers > 0
                                ? 'Todos já estão nesta lista.'
                                : widget.emptyText)
                            : 'Ninguém com esse nome.',
                        icon: LucideIcons.users,
                      ),
                    ),
                  for (final u in list)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: PsAvatar(
                        name: u.name,
                        url: u.avatar,
                        color: widget.color,
                      ),
                      title: Text(
                        u.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: u.email.isEmpty
                          ? null
                          : Text(
                              u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: u.id == widget.selectedId
                          ? Icon(LucideIcons.check, color: widget.color)
                          : Icon(LucideIcons.chevronRight,
                              size: 18, color: muted),
                      onTap: () =>
                          Navigator.of(context).pop(PsUserPick(u, flag: _flag)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
