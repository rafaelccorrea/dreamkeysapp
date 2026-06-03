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
    if (includeInactiveCompanyUsers) n++;
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
              : false,
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
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

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
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(LucideIcons.slidersHorizontal,
                        size: 18, color: textColor),
                    const SizedBox(width: 8),
                    Text(
                      'Filtros',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _draft = const UsersFilters();
                      }),
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _Section(
                      title: 'Papel',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Todos',
                            selected: _draft.role == null,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: null);
                            }),
                          ),
                          _Choice(
                            label: 'Master',
                            selected: _draft.role == 'master',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'master');
                            }),
                          ),
                          _Choice(
                            label: 'Admin',
                            selected: _draft.role == 'admin',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'admin');
                            }),
                          ),
                          _Choice(
                            label: 'Gerente',
                            selected: _draft.role == 'manager',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(role: 'manager');
                            }),
                          ),
                          _Choice(
                            label: 'Corretor',
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
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Qualquer',
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
                            selected: _draft.active == true,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(active: true);
                            }),
                          ),
                          _Choice(
                            label: 'Desativados',
                            selected: _draft.active == false,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(active: false);
                            }),
                          ),
                          _Choice(
                            label: 'Inativos na empresa',
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
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Qualquer',
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
                            selected: _draft.dateRange == 'today',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'today');
                            }),
                          ),
                          _Choice(
                            label: 'Semana',
                            selected: _draft.dateRange == 'week',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'week');
                            }),
                          ),
                          _Choice(
                            label: 'Mês',
                            selected: _draft.dateRange == 'month',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'month');
                            }),
                          ),
                          _Choice(
                            label: 'Nunca acessou',
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
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Com avatar',
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
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'A filtragem segue exatamente as regras da web '
                        '(usersApi.ts). Filtros avançados de data podem ser '
                        'adicionados em uma próxima iteração.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: secondaryColor,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(_draft),
                          child: const Text('Aplicar'),
                        ),
                      ),
                    ],
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textColor = ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
