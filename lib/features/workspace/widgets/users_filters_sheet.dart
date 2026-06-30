import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';

class UsersFilters {
  final String? role;
  final bool? active;
  final bool includeInactiveCompanyUsers;
  final bool? hasAvatar;
  final String? dateRange;
  final bool neverLoggedIn;
  final String? lastLoginFrom;
  final String? lastLoginTo;
  final bool onlyMyData;

  const UsersFilters({
    this.role,
    this.active,
    this.includeInactiveCompanyUsers = true,
    this.hasAvatar,
    this.dateRange,
    this.neverLoggedIn = false,
    this.lastLoginFrom,
    this.lastLoginTo,
    this.onlyMyData = false,
  });

  int get activeCount {
    int n = 0;
    if (role != null && role!.isNotEmpty) n++;
    if (active != null) n++;
    // `includeInactiveCompanyUsers` é `true` por padrão (baseline da lista).
    // Só conta como filtro quando o usuário DESLIGA (escolha não-padrão).
    if (!includeInactiveCompanyUsers) n++;
    if (hasAvatar != null) n++;
    if (dateRange != null && dateRange!.isNotEmpty) n++;
    if (neverLoggedIn) n++;
    if ((lastLoginFrom != null && lastLoginFrom!.isNotEmpty) ||
        (lastLoginTo != null && lastLoginTo!.isNotEmpty)) {
      n++;
    }
    if (onlyMyData) n++;
    return n;
  }

  UsersFilters copyWith({
    Object? role = _kSentinel,
    Object? active = _kSentinel,
    bool? includeInactiveCompanyUsers,
    Object? hasAvatar = _kSentinel,
    Object? dateRange = _kSentinel,
    bool? neverLoggedIn,
    Object? lastLoginFrom = _kSentinel,
    Object? lastLoginTo = _kSentinel,
    bool? onlyMyData,
  }) {
    return UsersFilters(
      role: role == _kSentinel ? this.role : role as String?,
      active: active == _kSentinel ? this.active : active as bool?,
      includeInactiveCompanyUsers:
          includeInactiveCompanyUsers ?? this.includeInactiveCompanyUsers,
      hasAvatar:
          hasAvatar == _kSentinel ? this.hasAvatar : hasAvatar as bool?,
      dateRange:
          dateRange == _kSentinel ? this.dateRange : dateRange as String?,
      neverLoggedIn: neverLoggedIn ?? this.neverLoggedIn,
      lastLoginFrom: lastLoginFrom == _kSentinel
          ? this.lastLoginFrom
          : lastLoginFrom as String?,
      lastLoginTo: lastLoginTo == _kSentinel
          ? this.lastLoginTo
          : lastLoginTo as String?,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }

  Map<String, dynamic> toMap() => {
        if (role != null) 'role': role,
        if (active != null) 'active': active,
        'includeInactiveCompanyUsers': includeInactiveCompanyUsers,
        if (hasAvatar != null) 'hasAvatar': hasAvatar,
        if (dateRange != null) 'dateRange': dateRange,
        'neverLoggedIn': neverLoggedIn,
        if (lastLoginFrom != null) 'lastLoginFrom': lastLoginFrom,
        if (lastLoginTo != null) 'lastLoginTo': lastLoginTo,
        'onlyMyData': onlyMyData,
      };

  factory UsersFilters.fromMap(Map<String, dynamic> m) {
    return UsersFilters(
      role: m['role']?.toString(),
      active: m['active'] is bool ? m['active'] as bool : null,
      includeInactiveCompanyUsers:
          m['includeInactiveCompanyUsers'] is bool
              ? m['includeInactiveCompanyUsers'] as bool
              : true,
      hasAvatar: m['hasAvatar'] is bool ? m['hasAvatar'] as bool : null,
      dateRange: m['dateRange']?.toString(),
      neverLoggedIn:
          m['neverLoggedIn'] is bool ? m['neverLoggedIn'] as bool : false,
      lastLoginFrom: m['lastLoginFrom']?.toString(),
      lastLoginTo: m['lastLoginTo']?.toString(),
      onlyMyData: m['onlyMyData'] is bool ? m['onlyMyData'] as bool : false,
    );
  }
}

const _kSentinel = Object();

class UsersFiltersSheet extends StatefulWidget {
  const UsersFiltersSheet({super.key, required this.initial});

  final UsersFilters initial;

  @override
  State<UsersFiltersSheet> createState() => _UsersFiltersSheetState();
}

class _UsersFiltersSheetState extends State<UsersFiltersSheet> {
  late UsersFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    // Acento ÚNICO e coerente para todo o modal (sem rainbow) — alinhado ao
    // acento da tela de Usuários. Ver memória color-strategy-subscreens.
    final accent = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    // Aliases mantidos para as seções usarem o mesmo tom coerente.
    final indigo = accent;
    final violet = accent;
    final emerald = accent;
    final blue = accent;
    final amber = accent;
    final activeCount = _draft.activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(
              color: indigo.withValues(alpha: isDark ? 0.22 : 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: indigo.withValues(alpha: isDark ? 0.18 : 0.1),
                        border:
                            Border.all(color: indigo.withValues(alpha: 0.28)),
                      ),
                      child: Icon(LucideIcons.slidersHorizontal,
                          size: 18, color: indigo),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtros',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.3,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeCount == 0
                                ? 'Refine a lista de usuários'
                                : '$activeCount filtro${activeCount == 1 ? '' : 's'} ativo${activeCount == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (activeCount > 0)
                      _ClearPill(
                        tone: indigo,
                        onTap: () =>
                            setState(() => _draft = const UsersFilters()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _Section(
                      title: 'Papel',
                      tone: violet,
                      icon: LucideIcons.shieldCheck,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Todos',
                            tone: violet,
                            selected: _draft.role == null,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: null);
                            }),
                          ),
                          _Choice(
                            label: 'Master',
                            tone: violet,
                            selected: _draft.role == 'master',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'master');
                            }),
                          ),
                          _Choice(
                            label: 'Admin',
                            tone: violet,
                            selected: _draft.role == 'admin',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'admin');
                            }),
                          ),
                          _Choice(
                            label: 'Gestor',
                            tone: violet,
                            selected: _draft.role == 'manager',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'manager');
                            }),
                          ),
                          _Choice(
                            label: 'Corretor',
                            tone: violet,
                            selected: _draft.role == 'user',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'user');
                            }),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Status',
                      tone: emerald,
                      icon: LucideIcons.activity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Qualquer',
                            tone: emerald,
                            selected: _draft.active == null &&
                                !_draft.includeInactiveCompanyUsers,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                active: null,
                                includeInactiveCompanyUsers: false,
                              );
                            }),
                          ),
                          _Choice(
                            label: 'Ativos',
                            tone: emerald,
                            selected: _draft.active == true,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(active: true);
                            }),
                          ),
                          _Choice(
                            label: 'Desativados',
                            tone: emerald,
                            selected: _draft.active == false,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(active: false);
                            }),
                          ),
                          _Choice(
                            label: 'Inativos na empresa',
                            tone: emerald,
                            selected: _draft.includeInactiveCompanyUsers,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                includeInactiveCompanyUsers:
                                    !_draft.includeInactiveCompanyUsers,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Último acesso',
                      tone: blue,
                      icon: LucideIcons.clock,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Qualquer',
                            tone: blue,
                            selected: _draft.dateRange == null &&
                                !_draft.neverLoggedIn,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                dateRange: null,
                                neverLoggedIn: false,
                              );
                            }),
                          ),
                          _Choice(
                            label: 'Hoje',
                            tone: blue,
                            selected: _draft.dateRange == 'today',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'today');
                            }),
                          ),
                          _Choice(
                            label: 'Semana',
                            tone: blue,
                            selected: _draft.dateRange == 'week',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'week');
                            }),
                          ),
                          _Choice(
                            label: 'Mês',
                            tone: blue,
                            selected: _draft.dateRange == 'month',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'month');
                            }),
                          ),
                          _Choice(
                            label: 'Nunca acessou',
                            tone: blue,
                            selected: _draft.neverLoggedIn,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                neverLoggedIn: !_draft.neverLoggedIn,
                                dateRange: null,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Outros',
                      tone: amber,
                      icon: LucideIcons.sparkles,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Com avatar',
                            tone: amber,
                            selected: _draft.hasAvatar == true,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                hasAvatar:
                                    _draft.hasAvatar == true ? null : true,
                              );
                            }),
                          ),
                          _Choice(
                            label: 'Sem avatar',
                            tone: amber,
                            selected: _draft.hasAvatar == false,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                hasAvatar:
                                    _draft.hasAvatar == false ? null : false,
                              );
                            }),
                          ),
                          _Choice(
                            label: 'Apenas meus dados',
                            tone: amber,
                            selected: _draft.onlyMyData,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                onlyMyData: !_draft.onlyMyData,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: ThemeHelpers.borderLightColor(context)),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textColor,
                              side: BorderSide(
                                color: ThemeHelpers.borderColor(context)
                                    .withValues(alpha: 0.7),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).pop(_draft),
                            style: FilledButton.styleFrom(
                              backgroundColor: indigo,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14.5),
                            ),
                            icon: const Icon(LucideIcons.check, size: 18),
                            label: Text(
                              activeCount == 0
                                  ? 'Aplicar filtros'
                                  : 'Aplicar ($activeCount)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pílula "Limpar" — só aparece quando há filtros ativos.
class _ClearPill extends StatelessWidget {
  const _ClearPill({required this.tone, required this.onTap});

  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: tone.withValues(alpha: 0.1),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.x, size: 13, color: tone),
              const SizedBox(width: 5),
              Text(
                'Limpar',
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    required this.tone,
    required this.icon,
  });

  final String title;
  final Widget child;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 12, color: tone),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? tone.withValues(alpha: isDark ? 0.2 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: isDark ? 0.6 : 0.45)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(LucideIcons.check, size: 13, color: tone),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? tone : textColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
