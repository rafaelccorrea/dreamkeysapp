import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/tag_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_meta.dart';
import '../utils/permission_rules.dart';

/// Peças de acesso compartilhadas por Criar e Editar usuário (gestores,
/// grade de permissões e folhas). Saíram de `edit_user_page.dart` para as
/// duas telas — irmãs no web — não divergirem.

// ───────────────────────────────────────────────────────────────────────────
// Gestor — chips + picker
// ───────────────────────────────────────────────────────────────────────────

/// Botão "Adicionar gestor" — fica sempre no topo da seção. Pill horizontal;
/// tom de alerta (vermelho) quando obrigatório e ainda sem gestor.
class UaAddGestorButton extends StatelessWidget {
  const UaAddGestorButton({
    super.key,
    required this.missing,
    required this.accent,
    required this.onTap,
  });
  final bool missing;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = missing ? AppColors.status.error : accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: missing ? 0.07 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.userPlus, size: 15, color: tone),
            const SizedBox(width: 7),
            Text(
              'Adicionar gestor',
              style: TextStyle(
                  color: tone, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip horizontal de um gestor vinculado — avatar + primeiro nome + remover.
class UaManagerChip extends StatelessWidget {
  const UaManagerChip({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.accent,
    required this.onRemove,
  });
  final String name;
  final String? avatarUrl;
  final Color accent;
  final VoidCallback onRemove;

  String get _first => name.trim().split(RegExp(r'\s+')).first;
  String get _initials {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1).toUpperCase();
    return '${p.first[0]}${p.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (avatarUrl ?? '').trim().isNotEmpty;
    final initialsBox = Container(
      width: 24,
      height: 24,
      color: accent,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(
            color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 24,
              height: 24,
              child: hasPhoto
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => initialsBox,
                      loadingBuilder: (_, child, prog) =>
                          prog == null ? child : initialsBox,
                    )
                  : initialsBox,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _first,
            style: TextStyle(
                color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(LucideIcons.x, size: 14, color: accent),
          ),
        ],
      ),
    );
  }
}

class UaManagerRow extends StatelessWidget {
  const UaManagerRow({
    super.key,
    required this.user,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final AdminUser user;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  String get _initials {
    final p = user.name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1).toUpperCase();
    return '${p.first[0]}${p.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Builder(builder: (_) {
              final hasPhoto = (user.avatar ?? '').trim().isNotEmpty;
              final initialsBox = Container(
                width: 34,
                height: 34,
                color: selected ? accent : secondary.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900),
                ),
              );
              return ClipOval(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: hasPhoto
                      ? Image.network(
                          user.avatar!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => initialsBox,
                          loadingBuilder: (_, child, prog) =>
                              prog == null ? child : initialsBox,
                        )
                      : initialsBox,
                ),
              );
            }),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${user.roleLabel} · ${user.email}',
                    style: TextStyle(fontSize: 11.5, color: secondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? LucideIcons.circleCheckBig : LucideIcons.circle,
              size: 20,
              color: selected ? accent : secondary.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Permissões — tile de categoria + linha no painel focado
// ───────────────────────────────────────────────────────────────────────────

class UaCategoryTile extends StatelessWidget {
  const UaCategoryTile({
    super.key,
    required this.category,
    required this.perms,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String category;
  final List<UserPermission> perms;
  final Set<String> selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = perms.length;
    final active = perms.where((p) => selected.contains(p.id)).length;
    final frac = total == 0 ? 0.0 : active / total;
    final on = active > 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? accent.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on
                ? accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: on
                        ? accent.withValues(alpha: 0.16)
                        : ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(PermissionMeta.categoryIcon(category),
                      size: 16, color: on ? accent : secondary),
                ),
                const Spacer(),
                if (on)
                  Text(
                    '$active/$total',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              PermissionMeta.categoryLabel(category),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
                height: 1.15,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            // Barra de progresso fina.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 3,
                backgroundColor:
                    ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              on ? '$active ativas' : 'nenhuma',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: on ? accent : secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UaPermRow extends StatelessWidget {
  const UaPermRow({
    super.key,
    required this.label,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.lockLabel,
  });
  final String label;
  final String? description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  /// Quando presente, a linha está travada (obrigatória, só administrador,
  /// proprietário) — o toque ainda chega para explicar o motivo.
  final String? lockLabel;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final locked = lockLabel != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? accent
                      : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? textColor : secondary,
                    ),
                  ),
                  if ((description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 8),
              Flexible(
                flex: 0,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.lock, size: 10, color: secondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          lockLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
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

// ───────────────────────────────────────────────────────────────────────────
// Sheet shell + busca (reuso entre gestor e permissões)
// ───────────────────────────────────────────────────────────────────────────

class UaSheetShell extends StatelessWidget {
  const UaSheetShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 10, 18, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondary),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class UaSheetSearch extends StatelessWidget {
  const UaSheetSearch({
    super.key,
    required this.controller,
    required this.accent,
    required this.onChanged,
  });
  final TextEditingController controller;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search, size: 16, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: accent,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                hintText: 'Buscar…',
                hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    fontSize: 13),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Seções compartilhadas (criar + editar)
// ───────────────────────────────────────────────────────────────────────────

/// Aviso inline (âmbar = trava/bloqueio; azul = informativo). Usado dentro
/// das folhas, onde o SnackBar da página ficaria escondido atrás do modal.
class UaNoticeBanner extends StatelessWidget {
  const UaNoticeBanner({super.key, required this.notice});

  final PermissionNotice notice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = notice.warning
        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.warning ? LucideIcons.triangleAlert : LucideIcons.info,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice.message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tone,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gestores responsáveis: botão de adicionar no topo + chips dos vinculados.
class UaManagerSelector extends StatelessWidget {
  const UaManagerSelector({
    super.key,
    required this.managers,
    required this.selected,
    required this.missing,
    required this.accent,
    required this.onAdd,
    required this.onRemove,
  });

  final List<AdminUser> managers;
  final Set<String> selected;
  final bool missing;
  final Color accent;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final chosen = managers.where((m) => selected.contains(m.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final unknown =
        selected.where((id) => managers.every((m) => m.id != id)).toList();
    final empty = chosen.isEmpty && unknown.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UaAddGestorButton(missing: missing, accent: accent, onTap: onAdd),
        if (empty && missing) ...[
          const SizedBox(height: 7),
          Text(
            'Obrigatório para corretores — selecione ao menos um gestor.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.status.error,
            ),
          ),
        ],
        if (!empty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in chosen)
                UaManagerChip(
                  name: m.name,
                  avatarUrl: m.avatar,
                  accent: accent,
                  onRemove: () => onRemove(m.id),
                ),
              for (final id in unknown)
                UaManagerChip(
                  name: 'Gestor',
                  avatarUrl: null,
                  accent: accent,
                  onRemove: () => onRemove(id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Folha de escolha de gestores (busca + lista marcável).
Future<void> showUaManagerSheet({
  required BuildContext context,
  required List<AdminUser> managers,
  required Set<String> selected,
  required Color accent,
  required ValueChanged<String> onToggle,
}) async {
  final searchCtrl = TextEditingController();
  String q = '';
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = managers.where((m) {
            if (q.isEmpty) return true;
            return m.name.toLowerCase().contains(q) ||
                m.email.toLowerCase().contains(q);
          }).toList();
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: UaSheetShell(
              title: 'Gestor responsável',
              subtitle: 'Toque para vincular ou remover.',
              accent: accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UaSheetSearch(
                    controller: searchCtrl,
                    accent: accent,
                    onChanged: (v) =>
                        setSheet(() => q = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Nenhum gestor encontrado.',
                              style: TextStyle(
                                color: ThemeHelpers.textSecondaryColor(ctx),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              return UaManagerRow(
                                user: m,
                                selected: selected.contains(m.id),
                                accent: accent,
                                onTap: () {
                                  onToggle(m.id);
                                  setSheet(() {});
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  searchCtrl.dispose();
}

/// Grade de categorias de permissão (2 colunas).
class UaPermissionGrid extends StatelessWidget {
  const UaPermissionGrid({
    super.key,
    required this.selection,
    required this.accent,
    required this.horizontalPadding,
    required this.onOpenCategory,
  });

  final PermissionSelection selection;
  final Color accent;
  final double horizontalPadding;
  final void Function(String category, List<UserPermission> perms)
      onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final w =
        (MediaQuery.sizeOf(context).width - (horizontalPadding * 2) - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in selection.categories)
          SizedBox(
            width: w,
            child: UaCategoryTile(
              category: entry.key,
              perms: entry.value,
              selected: selection.selected,
              accent: accent,
              onTap: () => onOpenCategory(entry.key, entry.value),
            ),
          ),
      ],
    );
  }
}

/// Folha de uma categoria: liga/desliga cada permissão com as regras do
/// web (fixas, dependências, alçada, proprietário). [onChanged] avisa a
/// página para redesenhar a grade.
Future<void> showUaPermissionCategorySheet({
  required BuildContext context,
  required PermissionSelection selection,
  required String category,
  required List<UserPermission> perms,
  required Color accent,
  required VoidCallback onChanged,
}) async {
  PermissionNotice? notice;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final ids = perms.map((p) => p.id).toSet();
          final allOn = ids.every(selection.selected.contains);
          final active =
              perms.where((p) => selection.selected.contains(p.id)).length;
          return UaSheetShell(
            title: PermissionMeta.categoryLabel(category),
            subtitle: '$active de ${perms.length} ativas',
            accent: accent,
            icon: PermissionMeta.categoryIcon(category),
            trailing: selection.ownerLocked
                ? null
                : TextButton.icon(
                    onPressed: () {
                      final n = selection.toggleCategory(category);
                      onChanged();
                      setSheet(() => notice = n);
                    },
                    style: TextButton.styleFrom(foregroundColor: accent),
                    icon: Icon(
                      allOn ? LucideIcons.squareCheckBig : LucideIcons.square,
                      size: 16,
                    ),
                    label: Text(allOn ? 'Limpar' : 'Tudo'),
                  ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notice != null) ...[
                  UaNoticeBanner(notice: notice!),
                  const SizedBox(height: 10),
                ],
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: perms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final p = perms[i];
                      return UaPermRow(
                        label: PermissionMeta.actionLabel(p.name),
                        description: PermissionMeta.permissionDescription(
                          p.name,
                          fallback: p.description,
                        ),
                        selected: selection.selected.contains(p.id),
                        accent: accent,
                        lockLabel: selection.lockReason(p),
                        onTap: () {
                          final n = selection.toggle(p.id);
                          onChanged();
                          setSheet(() => notice = n);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Tags do usuário (chips marcáveis) com teto — paridade com o
/// `TagSelector` do web (5 no cadastro, 10 na edição).
class UaTagSelector extends StatelessWidget {
  const UaTagSelector({
    super.key,
    required this.tags,
    required this.selected,
    required this.maxTags,
    required this.accent,
    required this.onToggle,
    this.loading = false,
    this.enabled = true,
  });

  final List<Tag> tags;
  final Set<String> selected;
  final int maxTags;
  final Color accent;
  final ValueChanged<String> onToggle;
  final bool loading;
  final bool enabled;

  Color _tagColor(Tag t) {
    final raw = (t.color ?? '').replaceAll('#', '').trim();
    if (raw.length == 6) {
      final v = int.tryParse(raw, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return accent;
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (loading) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          4,
          (i) => SkeletonBox(width: 70.0 + i * 12, height: 32, borderRadius: 999),
        ),
      );
    }
    if (tags.isEmpty) {
      return Text(
        'Nenhuma tag cadastrada na empresa.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: secondary,
        ),
      );
    }
    final atLimit = selected.length >= maxTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tags)
              Builder(builder: (context) {
                final on = selected.contains(t.id);
                final tone = _tagColor(t);
                final disabled = !enabled || (!on && atLimit);
                return GestureDetector(
                  onTap: disabled ? null : () => onToggle(t.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: on
                          ? tone.withValues(alpha: 0.12)
                          : ThemeHelpers.cardBackgroundColor(context),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on
                            ? tone.withValues(alpha: 0.55)
                            : ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tone,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: disabled
                                  ? secondary.withValues(alpha: 0.6)
                                  : (on
                                      ? ThemeHelpers.textColor(context)
                                      : secondary),
                            ),
                          ),
                        ),
                        if (on) ...[
                          const SizedBox(width: 5),
                          Icon(LucideIcons.check, size: 13, color: tone),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          atLimit
              ? 'Máximo de $maxTags tags atingido'
              : '${selected.length}/$maxTags selecionadas',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
      ],
    );
  }
}

/// Campo de escolha com a cara dos inputs `filled` da casa (abre folha).
class UaSelectField extends StatelessWidget {
  const UaSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final has = (value ?? '').isNotEmpty;
    return InkWell(
      onTap: enabled && !loading ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: !has && !loading,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          filled: true,
          fillColor: ThemeHelpers.cardBackgroundColor(context),
          prefixIcon: Icon(icon, size: 17, color: secondary),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SkeletonBox(width: 16, height: 16, borderRadius: 4),
                )
              : Icon(LucideIcons.chevronDown, size: 17, color: secondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Text(
          has ? value! : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }
}

/// Opção genérica de folha de escolha única.
class UaOption {
  final String? id;
  final String title;
  final String? subtitle;
  const UaOption({required this.id, required this.title, this.subtitle});
}

/// Folha de escolha única (com busca quando a lista é longa).
Future<UaOption?> showUaOptionSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<UaOption> options,
  required String? currentId,
  required Color accent,
}) {
  final searchCtrl = TextEditingController();
  String q = '';
  return showModalBottomSheet<UaOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = options.where((o) {
            if (q.isEmpty || o.id == null) return true;
            return o.title.toLowerCase().contains(q) ||
                (o.subtitle ?? '').toLowerCase().contains(q);
          }).toList();
          final textColor = ThemeHelpers.textColor(ctx);
          final secondary = ThemeHelpers.textSecondaryColor(ctx);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: UaSheetShell(
              title: title,
              subtitle: subtitle,
              accent: accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (options.length > 8) ...[
                    UaSheetSearch(
                      controller: searchCtrl,
                      accent: accent,
                      onChanged: (v) =>
                          setSheet(() => q = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        final on = o.id == currentId;
                        return GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(o),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: on
                                  ? accent.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: on
                                    ? accent.withValues(alpha: 0.4)
                                    : ThemeHelpers.borderColor(ctx)
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: o.id == null
                                              ? secondary
                                              : textColor,
                                        ),
                                      ),
                                      if ((o.subtitle ?? '').isNotEmpty)
                                        Text(
                                          o.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: secondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (on)
                                  Icon(
                                    LucideIcons.circleCheckBig,
                                    size: 18,
                                    color: accent,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(searchCtrl.dispose);
}

/// Cargo (escada da imobiliária) + superior direto — porte do
/// `CargoESuperiorFields` do web. Carrega a escada e os colegas; na edição
/// ([userId]) tira da lista de superiores a própria pessoa e quem está
/// abaixo dela (evita ciclo). Duas colunas quando cabe.
class UaHierarchyFields extends StatefulWidget {
  const UaHierarchyFields({
    super.key,
    required this.jobLevelId,
    required this.reportsToUserId,
    required this.accent,
    required this.onChanged,
    this.userId,
    this.enabled = true,
  });

  final String? jobLevelId;
  final String? reportsToUserId;
  final Color accent;
  final void Function(String? jobLevelId, String? reportsToUserId) onChanged;
  final String? userId;
  final bool enabled;

  @override
  State<UaHierarchyFields> createState() => _UaHierarchyFieldsState();
}

class _UaHierarchyFieldsState extends State<UaHierarchyFields> {
  bool _loading = true;
  List<JobLevelOption> _levels = const [];
  List<AdminUser> _colleagues = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.listJobLevels(),
      svc.listCompanyColleagues(),
    ]);
    if (!mounted) return;
    final levels = results[0];
    final colleagues = results[1];
    setState(() {
      _loading = false;
      if (levels.success && levels.data != null) {
        _levels = levels.data! as List<JobLevelOption>;
      }
      if (colleagues.success && colleagues.data != null) {
        _colleagues = colleagues.data! as List<AdminUser>;
      }
    });
  }

  List<AdminUser> get _superiors {
    final below = <String>{if (widget.userId != null) widget.userId!};
    var grew = widget.userId != null;
    while (grew) {
      grew = false;
      for (final c in _colleagues) {
        final r = c.reportsToUserId;
        if (r != null && below.contains(r) && !below.contains(c.id)) {
          below.add(c.id);
          grew = true;
        }
      }
    }
    final list = _colleagues.where((c) => !below.contains(c.id)).toList()
      ..sort((a, b) {
        final ra = a.jobLevelRank ?? 999;
        final rb = b.jobLevelRank ?? 999;
        if (ra != rb) return ra.compareTo(rb);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Future<void> _pickLevel() async {
    final picked = await showUaOptionSheet(
      context: context,
      title: 'Cargo',
      subtitle: 'Escada de cargos da imobiliária',
      accent: widget.accent,
      currentId: widget.jobLevelId,
      options: [
        const UaOption(id: null, title: 'Sem cargo'),
        for (final l in _levels) UaOption(id: l.id, title: l.name),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onChanged(picked.id, widget.reportsToUserId);
  }

  Future<void> _pickSuperior() async {
    final picked = await showUaOptionSheet(
      context: context,
      title: 'Superior direto',
      subtitle: 'A quem esta pessoa responde',
      accent: widget.accent,
      currentId: widget.reportsToUserId,
      options: [
        const UaOption(id: null, title: 'Sem superior'),
        for (final s in _superiors)
          UaOption(id: s.id, title: s.name, subtitle: s.jobLevelName),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onChanged(widget.jobLevelId, picked.id);
  }

  @override
  Widget build(BuildContext context) {
    String? levelName;
    for (final l in _levels) {
      if (l.id == widget.jobLevelId) levelName = l.name;
    }
    String? superiorName;
    for (final c in _colleagues) {
      if (c.id == widget.reportsToUserId) superiorName = c.name;
    }
    final level = UaSelectField(
      label: 'Cargo',
      value: _loading ? null : (levelName ?? 'Sem cargo'),
      icon: LucideIcons.idCard,
      accent: widget.accent,
      loading: _loading,
      enabled: widget.enabled,
      onTap: _pickLevel,
    );
    final superior = UaSelectField(
      label: 'Superior direto',
      value: _loading ? null : (superiorName ?? 'Sem superior'),
      icon: LucideIcons.userCog,
      accent: widget.accent,
      loading: _loading,
      enabled: widget.enabled,
      onTap: _pickSuperior,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth >= 360 &&
            MediaQuery.textScalerOf(context).scale(14) <= 16;
        if (!twoCols) {
          return Column(
            children: [level, const SizedBox(height: 12), superior],
          );
        }
        return Row(
          children: [
            Expanded(child: level),
            const SizedBox(width: 10),
            Expanded(child: superior),
          ],
        );
      },
    );
  }
}
