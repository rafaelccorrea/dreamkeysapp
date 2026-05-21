import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';

const _kSentinel = Object();

/// Filtros da listagem de equipes — paridade com web `TeamsFiltersDrawer`.
class TeamsFilters {
  final String? teamName;
  final String? memberName;
  final String? tag;
  final String? status; // 'active' | 'inactive' | 'all'
  final String? color;
  final String? dateRange;
  final bool onlyMyData;

  const TeamsFilters({
    this.teamName,
    this.memberName,
    this.tag,
    this.status,
    this.color,
    this.dateRange,
    this.onlyMyData = false,
  });

  int get activeCount {
    int n = 0;
    if ((teamName ?? '').isNotEmpty) n++;
    if ((memberName ?? '').isNotEmpty) n++;
    if ((tag ?? '').isNotEmpty) n++;
    if ((status ?? '').isNotEmpty) n++;
    if ((color ?? '').isNotEmpty) n++;
    if ((dateRange ?? '').isNotEmpty) n++;
    if (onlyMyData) n++;
    return n;
  }

  TeamsFilters copyWith({
    Object? teamName = _kSentinel,
    Object? memberName = _kSentinel,
    Object? tag = _kSentinel,
    Object? status = _kSentinel,
    Object? color = _kSentinel,
    Object? dateRange = _kSentinel,
    bool? onlyMyData,
  }) {
    return TeamsFilters(
      teamName: teamName == _kSentinel ? this.teamName : teamName as String?,
      memberName:
          memberName == _kSentinel ? this.memberName : memberName as String?,
      tag: tag == _kSentinel ? this.tag : tag as String?,
      status: status == _kSentinel ? this.status : status as String?,
      color: color == _kSentinel ? this.color : color as String?,
      dateRange:
          dateRange == _kSentinel ? this.dateRange : dateRange as String?,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }

  Map<String, dynamic> toMap() => {
        if (teamName != null) 'teamName': teamName,
        if (memberName != null) 'memberName': memberName,
        if (tag != null) 'tag': tag,
        if (status != null) 'status': status,
        if (color != null) 'color': color,
        if (dateRange != null) 'dateRange': dateRange,
        'onlyMyData': onlyMyData,
      };

  factory TeamsFilters.fromMap(Map<String, dynamic> m) {
    return TeamsFilters(
      teamName: m['teamName']?.toString(),
      memberName: m['memberName']?.toString(),
      tag: m['tag']?.toString(),
      status: m['status']?.toString(),
      color: m['color']?.toString(),
      dateRange: m['dateRange']?.toString(),
      onlyMyData: m['onlyMyData'] is bool ? m['onlyMyData'] as bool : false,
    );
  }
}

const List<String> kTeamSwatches = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#EC4899',
  '#06B6D4',
  '#84CC16',
  '#F97316',
  '#6366F1',
  '#14B8A6',
  '#A855F7',
  '#22C55E',
  '#D946EF',
  '#0EA5E9',
];

class TeamsFiltersSheet extends StatefulWidget {
  const TeamsFiltersSheet({super.key, required this.initial});

  final TeamsFilters initial;

  @override
  State<TeamsFiltersSheet> createState() => _TeamsFiltersSheetState();
}

class _TeamsFiltersSheetState extends State<TeamsFiltersSheet> {
  late TeamsFilters _draft;
  final TextEditingController _teamNameCtrl = TextEditingController();
  final TextEditingController _memberNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _teamNameCtrl.text = _draft.teamName ?? '';
    _memberNameCtrl.text = _draft.memberName ?? '';
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _memberNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);

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
                        _draft = const TeamsFilters();
                        _teamNameCtrl.clear();
                        _memberNameCtrl.clear();
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
                      title: 'Nome da equipe',
                      child: TextField(
                        controller: _teamNameCtrl,
                        onChanged: (v) => _draft = _draft.copyWith(
                          teamName: v.isEmpty ? null : v,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Ex.: Médio 1',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    _Section(
                      title: 'Membro',
                      child: TextField(
                        controller: _memberNameCtrl,
                        onChanged: (v) => _draft = _draft.copyWith(
                          memberName: v.isEmpty ? null : v,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nome do membro',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    _Section(
                      title: 'Status',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Todas',
                            selected: _draft.status == null,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(status: null);
                            }),
                          ),
                          _Choice(
                            label: 'Ativas',
                            selected: _draft.status == 'active',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(status: 'active');
                            }),
                          ),
                          _Choice(
                            label: 'Inativas',
                            selected: _draft.status == 'inactive',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(status: 'inactive');
                            }),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Cor',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(color: null);
                            }),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ThemeHelpers.borderColor(context)
                                    .withValues(alpha: 0.25),
                                border: Border.all(
                                  color: _draft.color == null
                                      ? Theme.of(context).colorScheme.primary
                                      : ThemeHelpers.borderColor(context),
                                  width: _draft.color == null ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(LucideIcons.x,
                                  size: 14, color: textColor),
                            ),
                          ),
                          for (final hex in kTeamSwatches)
                            GestureDetector(
                              onTap: () => setState(() {
                                _draft = _draft.copyWith(color: hex);
                              }),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _parseHex(hex),
                                  border: Border.all(
                                    color: _draft.color == hex
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: _draft.color == hex
                                      ? [
                                          BoxShadow(
                                            color: _parseHex(hex)
                                                .withValues(alpha: 0.55),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Criação',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Choice(
                            label: 'Qualquer',
                            selected: _draft.dateRange == null,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: null);
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
                            label: 'Ano',
                            selected: _draft.dateRange == 'year',
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(dateRange: 'year');
                            }),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Escopo',
                      child: _Choice(
                        label: 'Apenas equipes criadas por mim',
                        selected: _draft.onlyMyData,
                        onTap: () => setState(() {
                          _draft = _draft.copyWith(
                            onlyMyData: !_draft.onlyMyData,
                          );
                        }),
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

Color _parseHex(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse('FF$h', radix: 16) ?? 0xFF888888;
  return Color(v);
}
