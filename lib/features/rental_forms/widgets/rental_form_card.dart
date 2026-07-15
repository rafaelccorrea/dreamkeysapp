import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/rental_form_model.dart';

/// Card de uma ficha de locação na listagem — mesma gramática do
/// `SaleFormCard`: card flush sem borda lateral, status como pill tonal,
/// ações no próprio item (menu ⋯), rodapé com responsável/envolvidos/datas.
class RentalFormCard extends StatelessWidget {
  const RentalFormCard({
    super.key,
    required this.form,
    required this.accent,
    this.onTap,
    this.onReopen,
    this.onShareSignature,
    this.onDelete,
  });

  final RentalForm form;
  final Color accent;
  final VoidCallback? onTap;

  /// Reabrir para edição (finalizada/aguardando → pendente).
  final VoidCallback? onReopen;

  /// Compartilhar link de assinatura (aguardando assinatura).
  final VoidCallback? onShareSignature;
  final VoidCallback? onDelete;

  Color _statusTone(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (form.status) {
      case RentalFormStatus.finalized:
        return dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case RentalFormStatus.awaitingSignature:
        return dark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case RentalFormStatus.canceled:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case RentalFormStatus.pending:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = _statusTone(context);

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final created = form.createdAt != null
        ? dateFmt.format(form.createdAt!.toLocal())
        : null;
    final submitted = form.submittedAt != null
        ? dateFmt.format(form.submittedAt!.toLocal())
        : null;

    final involved = form.involvedUsers;
    final hasPublicLink = (form.publicToken ?? '').isNotEmpty;
    final showMenu =
        onReopen != null || onShareSignature != null || onDelete != null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: isDark ? 0.9 : 0.8),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                  spreadRadius: -8,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 8, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho: status + título + menu ─────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _StatusPill(
                                tone: tone,
                                label: form.status.label.toUpperCase(),
                              ),
                              if (hasPublicLink) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.link_rounded,
                                    size: 15, color: muted),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            form.title?.trim().isNotEmpty == true
                                ? form.title!
                                : '(sem título)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (showMenu)
                      _MoreMenu(
                        onReopen: onReopen,
                        onShareSignature: onShareSignature,
                        onDelete: onDelete,
                      ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: ThemeHelpers.borderLightColor(
                    context,
                  ).withValues(alpha: 0.7),
                ),
                const SizedBox(height: 12),

                // ── Responsável + envolvidos ──────────────────────
                Row(
                  children: [
                    _Avatar(
                      initials: form.createdBy?.initials ?? '?',
                      accent: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            form.responsibleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          Text(
                            involved.isEmpty
                                ? 'Sem envolvidos'
                                : involved.length == 1
                                    ? '1 envolvido'
                                    : '${involved.length} envolvidos',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (involved.isNotEmpty)
                      _AvatarStack(users: involved, accent: accent),
                  ],
                ),

                // ── Rodapé: datas ─────────────────────────────────
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (created != null)
                      _MetaItem(
                        icon: Icons.schedule_outlined,
                        text: 'Criada $created',
                      ),
                    if (submitted != null)
                      _MetaItem(
                        icon: Icons.verified_outlined,
                        text: 'Finalizada $submitted',
                        tone: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.status.successDarkMode
                            : AppColors.status.success,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton **fiel** ao [RentalFormCard] — mesmo container, pill de status,
/// título, divisória, linha responsável/avatars e rodapé de datas.
class RentalFormCardSkeleton extends StatelessWidget {
  const RentalFormCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(
            context,
          ).withValues(alpha: isDark ? 0.9 : 0.8),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 5),
              spreadRadius: -8,
            ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status pill
          const SkeletonBox(width: 110, height: 20, borderRadius: 999),
          const SizedBox(height: 11),
          // Título
          Row(
            children: const [
              Expanded(flex: 7, child: SkeletonText(height: 18)),
              Spacer(flex: 3),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(width: double.infinity, height: 1),
          const SizedBox(height: 14),
          // Responsável + avatars
          Row(
            children: const [
              SkeletonBox(width: 30, height: 30, borderRadius: 999),
              SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 120, height: 12),
                    SizedBox(height: 6),
                    SkeletonText(width: 76, height: 10),
                  ],
                ),
              ),
              Spacer(flex: 2),
              SkeletonBox(width: 52, height: 24, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 14),
          // Datas
          Row(
            children: const [
              SkeletonBox(width: 128, height: 12, borderRadius: 6),
              SizedBox(width: 12),
              SkeletonBox(width: 96, height: 12, borderRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tone, required this.label});
  final Color tone;
  final String label;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.accent, this.size = 30});
  final String initials;
  final Color accent;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.13),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Pilha de avatares dos envolvidos (máx. 3 + contador).
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.users, required this.accent});
  final List<RentalFormUser> users;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final shown = users.take(3).toList();
    final extra = users.length - shown.length;
    const overlap = 16.0;
    final width = 24 + (shown.length - 1) * overlap + (extra > 0 ? 22 : 0);
    return SizedBox(
      height: 24,
      width: width.toDouble(),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ThemeHelpers.cardBackgroundColor(context),
                    width: 1.6,
                  ),
                ),
                child:
                    _Avatar(initials: shown[i].initials, accent: accent, size: 22),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * overlap + 2,
              top: 5,
              child: Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text, this.tone});
  final IconData icon;
  final String text;
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final muted = tone ?? ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({this.onReopen, this.onShareSignature, this.onDelete});
  final VoidCallback? onReopen;
  final VoidCallback? onShareSignature;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    return PopupMenuButton<String>(
      tooltip: 'Ações da ficha',
      padding: EdgeInsets.zero,
      splashRadius: 20,
      offset: const Offset(0, 10),
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
        ),
      ),
      icon: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.more_horiz_rounded, size: 19, color: muted),
      ),
      itemBuilder: (ctx) => [
        if (onShareSignature != null)
          _item('assinatura', Icons.draw_outlined, 'Link de assinatura',
              green, textColor),
        if (onReopen != null)
          _item('reabrir', Icons.edit_outlined, 'Reabrir para edição', warn,
              textColor),
        if (onDelete != null)
          _item('excluir', Icons.delete_outline_rounded, 'Excluir', danger,
              danger),
      ],
      onSelected: (v) {
        switch (v) {
          case 'assinatura':
            onShareSignature?.call();
            break;
          case 'reabrir':
            onReopen?.call();
            break;
          case 'excluir':
            onDelete?.call();
            break;
        }
      },
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    Color iconColor,
    Color textColor,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 11),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
          ),
        ],
      ),
    );
  }
}
