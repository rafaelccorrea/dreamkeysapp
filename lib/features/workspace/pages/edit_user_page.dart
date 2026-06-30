import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_meta.dart';

/// Acento por papel — torna a subtela coerente com QUEM se edita (Corretor,
/// Gerente, Admin, Master). O vermelho da marca fica reservado para a ação
/// principal (Salvar). Ver memória `color-strategy-subscreens`.
/// Cores por papel — alinhadas ao hero da tela de Usuários (fonte de verdade):
/// Corretor = verde, Gestor = azul/indigo, Admin = roxo. O conforto vem do
/// uso TONAL (sem preenchimento neon) no segmented. Ver
/// memória color-strategy-subscreens.
Color _roleAccent(String role, bool isDark) {
  switch (role) {
    case 'master':
      // Distinto do Admin (roxo mais profundo).
      return isDark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9);
    case 'admin':
      return isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED); // roxo
    case 'manager':
      return isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1); // azul
    case 'user':
    default:
      return isDark ? const Color(0xFF34D399) : const Color(0xFF059669); // verde
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'master':
      return 'Master';
    case 'admin':
      return 'Administrador';
    case 'manager':
      return 'Gestor';
    default:
      return 'Corretor';
  }
}

/// Tela de **Editar Usuário** (mobile, identidade própria — sem banner, flush).
/// Permite alterar papel, gestor responsável (obrigatório p/ corretor), acesso
/// ao app e permissões (grade de categorias → painel focado).
class EditUserPage extends StatefulWidget {
  const EditUserPage({super.key, required this.user});

  final AdminUser user;

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const double _padH = 20;
  static const double _gap = 20; // espaçamento entre seções (enxuto)

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final List<MapEntry<String, List<UserPermission>>> _catalog = [];
  List<AdminUser> _managers = [];

  /// Usuário exibido no hero — começa com o item da lista e é substituído pelo
  /// detalhe (`GET /admin/users/:id`), que traz `lastLogin`, documento, etc.
  late AdminUser _user;

  late String _role;
  late bool _hasAppAccess;
  Set<String> _selectedPerms = {};
  Set<String> _selectedManagers = {};

  // Snapshot inicial p/ detectar alterações.
  late String _role0;
  late bool _app0;
  Set<String> _perms0 = {};
  Set<String> _managers0 = {};

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent => _roleAccent(_role, _isDark);
  Color get _brandRed =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  bool get _isUser => _role == 'user';
  bool get _isPrivileged => _role == 'admin' || _role == 'master';

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _role = widget.user.role.toLowerCase();
    _hasAppAccess = widget.user.hasAppAccess;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.getUserById(widget.user.id),
      svc.getPermissionCatalog(),
      svc.listManagers(),
    ]);
    if (!mounted) return;
    final detailRes = results[0];
    final catalogRes = results[1];
    final managersRes = results[2];

    if (catalogRes.success && catalogRes.data != null) {
      final data = catalogRes.data! as Map<String, List<UserPermission>>;
      final entries = data.entries.where((e) => e.value.isNotEmpty).toList()
        ..sort((a, b) => PermissionMeta.categoryLabel(a.key)
            .toLowerCase()
            .compareTo(PermissionMeta.categoryLabel(b.key).toLowerCase()));
      _catalog
        ..clear()
        ..addAll(entries);
    }
    if (managersRes.success && managersRes.data != null) {
      _managers = (managersRes.data! as List<AdminUser>)
          .where((m) => m.id != widget.user.id)
          .toList();
    }
    if (detailRes.success && detailRes.data != null) {
      final u = detailRes.data! as AdminUser;
      _user = u;
      _role = u.role.toLowerCase();
      _hasAppAccess = u.hasAppAccess;
      _selectedPerms = {...u.permissionIds};
      _selectedManagers = {...u.managerIds};
    } else {
      _selectedPerms = {...widget.user.permissionIds};
      _selectedManagers = {...widget.user.managerIds};
    }

    _role0 = _role;
    _app0 = _hasAppAccess;
    _perms0 = {..._selectedPerms};
    _managers0 = {..._selectedManagers};

    setState(() {
      _loading = false;
      if (!catalogRes.success && _catalog.isEmpty) {
        _error =
            catalogRes.message ?? 'Não foi possível carregar as permissões.';
      }
    });
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _dirty =>
      _role != _role0 ||
      (_isUser && _hasAppAccess != _app0) ||
      (_isUser && !_setEquals(_selectedManagers, _managers0)) ||
      !_setEquals(_selectedPerms, _perms0);

  bool get _managerMissing => _isUser && _selectedManagers.isEmpty;

  int get _totalPerms => _catalog.fold(0, (s, e) => s + e.value.length);

  Future<void> _save() async {
    if (_saving) return;
    if (_managerMissing) {
      _snack('Selecione ao menos um gestor para o corretor.', error: true);
      return;
    }
    if (!_dirty) return;
    setState(() => _saving = true);

    // 1) Acesso ao app via endpoint dedicado (espelha o web), se mudou.
    if (_isUser && _hasAppAccess != _app0) {
      final r = await AdminUsersService.instance
          .updateAppAccess(widget.user.id, _hasAppAccess);
      if (!mounted) return;
      if (!r.success) {
        setState(() => _saving = false);
        _snack(r.message ?? 'Falha ao atualizar acesso ao app.', error: true);
        return;
      }
    }

    // 2) Papel / gestores / permissões.
    final res = await AdminUsersService.instance.updateUser(
      widget.user.id,
      role: _role != _role0 ? _role : null,
      managerIds: _isUser ? _selectedManagers.toList() : null,
      permissionIds: _selectedPerms.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Falha ao salvar.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Editar usuário',
      showBottomNavigation: false,
      body: _loading
          ? _buildSkeleton()
          : Column(
              children: [
                Expanded(child: _buildContent()),
                _buildSaveBar(),
              ],
            ),
    );
  }

  // ─── Conteúdo ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 20),
      children: [
        _FlushHero(user: _user, role: _role, accent: _accent),
        const SizedBox(height: _gap),
        // Sem título (só "Permissões" tem): o segmented já é autoexplicativo.
        _RoleSegmented(
          current: _role,
          includeMaster: _role0 == 'master',
          onChanged: (r) => setState(() => _role = r),
        ),
        if (_isUser) ...[
          const SizedBox(height: 14),
          _buildManagerSelector(),
          const SizedBox(height: 14),
          _buildAppAccessRow(),
        ],
        const SizedBox(height: _gap),
        _SectionLabel(
          icon: LucideIcons.shieldCheck,
          label: 'PERMISSÕES',
          accent: _accent,
          trailing: _CountPill(
            text: '${_selectedPerms.length}/$_totalPerms',
            color: _accent,
          ),
        ),
        const SizedBox(height: 11),
        if (_isPrivileged) ...[
          _PrivilegedNote(role: _role),
          const SizedBox(height: 11),
        ],
        if (_error != null && _catalog.isEmpty)
          _ErrorInline(message: _error!, onRetry: _bootstrap)
        else
          _buildPermissionGrid(),
      ],
    );
  }

  // ─── Gestor ─────────────────────────────────────────────────────────────

  Widget _buildManagerSelector() {
    final selected = _managers.where((m) => _selectedManagers.contains(m.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final unknown = _selectedManagers
        .where((id) => _managers.every((m) => m.id != id))
        .toList();
    final empty = selected.isEmpty && unknown.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Botão de adicionar SEMPRE no topo da seção.
        _AddGestorButton(
          missing: _managerMissing,
          accent: _accent,
          onTap: _openManagerSheet,
        ),
        if (empty && _managerMissing) ...[
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
          // Chips horizontais (wrap), ordenados.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in selected)
                _ManagerChip(
                  name: m.name,
                  accent: _accent,
                  onRemove: () =>
                      setState(() => _selectedManagers.remove(m.id)),
                ),
              for (final id in unknown)
                _ManagerChip(
                  name: 'Gestor',
                  accent: _accent,
                  onRemove: () => setState(() => _selectedManagers.remove(id)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openManagerSheet() async {
    final searchCtrl = TextEditingController();
    String q = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final filtered = _managers.where((m) {
              if (q.isEmpty) return true;
              return m.name.toLowerCase().contains(q) ||
                  m.email.toLowerCase().contains(q);
            }).toList();
            return _SheetShell(
              title: 'Gestor responsável',
              subtitle: 'Toque para vincular ou remover.',
              accent: _accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetSearch(
                    controller: searchCtrl,
                    accent: _accent,
                    onChanged: (v) => setSheet(() => q = v.trim().toLowerCase()),
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
                            separatorBuilder: (_, _) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              final on = _selectedManagers.contains(m.id);
                              return _ManagerRow(
                                user: m,
                                selected: on,
                                accent: _accent,
                                onTap: () {
                                  setState(() {
                                    if (on) {
                                      _selectedManagers.remove(m.id);
                                    } else {
                                      _selectedManagers.add(m.id);
                                    }
                                  });
                                  setSheet(() {});
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
    searchCtrl.dispose();
  }

  // ─── Acesso ao app ───────────────────────────────────────────────────────

  Widget _buildAppAccessRow() {
    final on = _hasAppAccess;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: () => setState(() => _hasAppAccess = !on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: on ? _accent.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on
                ? _accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: on
                    ? _accent.withValues(alpha: 0.16)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.smartphone,
                  size: 17, color: on ? _accent : secondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Permitir uso do app móvel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    on
                        ? 'O corretor pode entrar no aplicativo.'
                        : 'Acesso ao aplicativo bloqueado.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: on ? _accent : secondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: on,
              onChanged: (v) => setState(() => _hasAppAccess = v),
              activeTrackColor: _accent,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Permissões (grade → painel focado) ───────────────────────────────────

  Widget _buildPermissionGrid() {
    final w = (MediaQuery.sizeOf(context).width - (_padH * 2) - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in _catalog)
          SizedBox(
            width: w,
            child: _CategoryTile(
              category: entry.key,
              perms: entry.value,
              selected: _selectedPerms,
              accent: _accent,
              onTap: () => _openCategorySheet(entry.key, entry.value),
            ),
          ),
      ],
    );
  }

  Future<void> _openCategorySheet(
      String category, List<UserPermission> perms) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final ids = perms.map((p) => p.id).toSet();
            final allOn = ids.every(_selectedPerms.contains);
            final active = perms.where((p) => _selectedPerms.contains(p.id))
                .length;
            return _SheetShell(
              title: PermissionMeta.categoryLabel(category),
              subtitle: '$active de ${perms.length} ativas',
              accent: _accent,
              icon: PermissionMeta.categoryIcon(category),
              trailing: TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (allOn) {
                      _selectedPerms.removeAll(ids);
                    } else {
                      _selectedPerms.addAll(ids);
                    }
                  });
                  setSheet(() {});
                },
                style: TextButton.styleFrom(foregroundColor: _accent),
                icon: Icon(
                    allOn ? LucideIcons.squareCheckBig : LucideIcons.square,
                    size: 16),
                label: Text(allOn ? 'Limpar' : 'Tudo'),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: perms.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final p = perms[i];
                  final on = _selectedPerms.contains(p.id);
                  return _PermRow(
                    label: PermissionMeta.actionLabel(p.name),
                    description: p.description,
                    selected: on,
                    accent: _accent,
                    onTap: () {
                      setState(() {
                        if (on) {
                          _selectedPerms.remove(p.id);
                        } else {
                          _selectedPerms.add(p.id);
                        }
                      });
                      setSheet(() {});
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  // ─── Save bar ─────────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    final blocked = _managerMissing;
    final canSave = _dirty && !_saving && !blocked;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          _padH, 12, _padH, 12 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          if (_dirty) ...[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Descartar'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: _brandRed,
                disabledBackgroundColor:
                    ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : blocked
                        ? 'Selecione um gestor'
                        : (_dirty ? 'Salvar alterações' : 'Tudo salvo'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    letterSpacing: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Skeleton ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 20),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            SkeletonBox(width: 60, height: 60, borderRadius: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 160, height: 16, borderRadius: 6),
                  SizedBox(height: 8),
                  SkeletonBox(width: 200, height: 12, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
        const SizedBox(height: 22),
        SkeletonBox(width: 120, height: 11, borderRadius: 999),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            6,
            (_) => SkeletonBox(
              width: (MediaQuery.sizeOf(context).width - (_padH * 2) - 12) / 2,
              height: 84,
              borderRadius: 16,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Hero flush (sem card) — identidade + metadados
// ───────────────────────────────────────────────────────────────────────────

class _FlushHero extends StatelessWidget {
  const _FlushHero({required this.user, required this.role, required this.accent});

  final AdminUser user;
  final String role;
  final Color accent;

  ({Color color, String label, IconData icon}) _presence() {
    if (!user.isActiveInCompany || !user.active) {
      return (color: const Color(0xFFA1A1AA), label: 'Desativado', icon: LucideIcons.minus);
    }
    if (user.neverLoggedIn) {
      return (color: const Color(0xFFF59E0B), label: 'Nunca acessou', icon: LucideIcons.clock);
    }
    return (color: const Color(0xFF10B981), label: 'Ativo', icon: LucideIcons.check);
  }

  String? _maskedDoc() {
    final raw = user.document;
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 2) return '***.***.***-**';
    return '***.***.***-${d.substring(d.length - 2)}';
  }

  String _initials() {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final presence = _presence();
    final hasPhoto = (user.avatar ?? '').trim().isNotEmpty;
    final deep = HSLColor.fromColor(accent)
        .withLightness(
            (HSLColor.fromColor(accent).lightness * 0.78).clamp(0.0, 1.0))
        .toColor();

    final lastLogin = user.lastLoginAt != null
        ? DateFormat("d 'de' MMM · HH:mm", 'pt_BR')
            .format(user.lastLoginAt!.toLocal())
        : 'Nunca';
    final created = user.createdAt != null
        ? DateFormat("d 'de' MMM yyyy", 'pt_BR').format(user.createdAt!.toLocal())
        : '—';

    final avatarInner = hasPhoto
        ? Image.network(user.avatar!, width: 60, height: 60, fit: BoxFit.cover)
        : Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, deep],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.32)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarInner,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: presence.color,
                        border: Border.all(color: cardColor, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: presence.color.withValues(alpha: 0.55),
                            blurRadius: 6,
                            spreadRadius: 0.4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isEmpty ? '—' : user.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                      height: 1.05,
                      fontSize: 20,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(LucideIcons.mail, size: 12, color: secondary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MiniBadge(
                        label: _roleLabel(role),
                        color: accent,
                        icon: LucideIcons.shieldCheck,
                        isDark: isDark,
                      ),
                      _MiniBadge(
                        label: presence.label,
                        color: presence.color,
                        icon: presence.icon,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.9)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.phone,
                label: 'TELEFONE',
                value: (user.phone?.trim().isNotEmpty == true)
                    ? user.phone!.trim()
                    : '—',
              ),
            ),
            _metaDivider(context),
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.fingerprint,
                label: 'CPF',
                value: _maskedDoc() ?? '—',
                monospace: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.clock,
                label: 'ÚLTIMO ACESSO',
                value: lastLogin,
                valueColor: user.neverLoggedIn ? const Color(0xFFF59E0B) : null,
              ),
            ),
            _metaDivider(context),
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.calendar,
                label: 'MEMBRO DESDE',
                value: created,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaDivider(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Section label (flush, com filete + trailing)
// ───────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 12, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Papel — segmented (cada papel na sua cor)
// ───────────────────────────────────────────────────────────────────────────

class _RoleSegmented extends StatelessWidget {
  const _RoleSegmented({
    required this.current,
    required this.includeMaster,
    required this.onChanged,
  });

  final String current;
  final bool includeMaster;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <({String value, String label, IconData icon})>[
      (value: 'user', label: 'Corretor', icon: LucideIcons.user),
      (value: 'manager', label: 'Gestor', icon: LucideIcons.briefcase),
      (value: 'admin', label: 'Admin', icon: LucideIcons.shieldCheck),
      if (includeMaster)
        (value: 'master', label: 'Master', icon: LucideIcons.crown),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: _RoleChip(
                label: it.label,
                icon: it.icon,
                selected: current == it.value,
                color: _roleAccent(it.value, isDark),
                onTap: () => onChanged(it.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? color : ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          // Tonal suave (sem preenchimento saturado nem brilho) — conforto.
          color: selected
              ? color.withValues(alpha: isDark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: isDark ? 0.5 : 0.38)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Gestor — chips + picker
// ───────────────────────────────────────────────────────────────────────────

/// Botão "Adicionar gestor" — fica sempre no topo da seção. Pill horizontal;
/// tom de alerta (vermelho) quando obrigatório e ainda sem gestor.
class _AddGestorButton extends StatelessWidget {
  const _AddGestorButton({
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
class _ManagerChip extends StatelessWidget {
  const _ManagerChip(
      {required this.name, required this.accent, required this.onRemove});
  final String name;
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
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900),
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

class _ManagerRow extends StatelessWidget {
  const _ManagerRow({
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
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : secondary.withValues(alpha: 0.25),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900),
              ),
            ),
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
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

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final String? description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
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
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Sheet shell + busca (reuso entre gestor e permissões)
// ───────────────────────────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  const _SheetShell({
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

class _SheetSearch extends StatelessWidget {
  const _SheetSearch({
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
// Reuso: badges / meta / notas
// ───────────────────────────────────────────────────────────────────────────

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.36 : 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDatum extends StatelessWidget {
  const _MetaDatum({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: secondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: secondary,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? textColor,
            letterSpacing: monospace ? 0.4 : -0.1,
            fontFamily: monospace ? 'monospace' : null,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PrivilegedNote extends StatelessWidget {
  const _PrivilegedNote({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${role == 'master' ? 'Master' : 'Administradores'} têm acesso '
              'total — as permissões abaixo são ignoradas pelo sistema.',
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

class _ErrorInline extends StatelessWidget {
  const _ErrorInline({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(LucideIcons.cloudOff,
              size: 30, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
