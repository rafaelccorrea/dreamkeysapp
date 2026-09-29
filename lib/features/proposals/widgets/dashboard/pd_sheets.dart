import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

// ─── Período ─────────────────────────────────────────────────────────────

final DateFormat _ymd = DateFormat('yyyy-MM-dd');
final DateFormat _dmy = DateFormat('dd/MM/yyyy');

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class PdPeriod {
  /// `null` quando o intervalo é personalizado.
  final String? presetId;
  final DateTime from;
  final DateTime to;

  /// day | week | month.
  final String granularity;

  const PdPeriod({
    required this.presetId,
    required this.from,
    required this.to,
    required this.granularity,
  });

  String get dateFrom => _ymd.format(from);
  String get dateTo => _ymd.format(to);

  String get title {
    final id = presetId;
    if (id != null) {
      for (final p in pdPresets) {
        if (p.id == id) return p.label;
      }
    }
    return 'Intervalo personalizado';
  }

  String get rangeLabel => _day(from) == _day(to)
      ? _dmy.format(from)
      : '${_dmy.format(from)} – ${_dmy.format(to)}';

  String get granularityLabel => pdGranularityLabel(granularity);

  /// Padrão do web: mês atual, granularidade diária.
  factory PdPeriod.initial() => pdPresets
      .firstWhere((p) => p.id == 'mtd', orElse: () => pdPresets.first)
      .compute();
}

class PdPreset {
  final String id;
  final String label;
  final PdPeriod Function() compute;

  const PdPreset(this.id, this.label, this.compute);
}

PdPeriod _p(String id, DateTime from, DateTime to, String g) =>
    PdPeriod(presetId: id, from: _day(from), to: _day(to), granularity: g);

/// Atalhos idênticos aos do web (`FichasFiltersBar`).
final List<PdPreset> pdPresets = [
  PdPreset('today', 'Hoje', () {
    final d = DateTime.now();
    return _p('today', d, d, 'day');
  }),
  PdPreset('yesterday', 'Ontem', () {
    final d = _day(DateTime.now()).subtract(const Duration(days: 1));
    return _p('yesterday', d, d, 'day');
  }),
  PdPreset('7d', '7 dias', () {
    final d = _day(DateTime.now());
    return _p('7d', d.subtract(const Duration(days: 6)), d, 'day');
  }),
  PdPreset('14d', '14 dias', () {
    final d = _day(DateTime.now());
    return _p('14d', d.subtract(const Duration(days: 13)), d, 'day');
  }),
  PdPreset('30d', '30 dias', () {
    final d = _day(DateTime.now());
    return _p('30d', d.subtract(const Duration(days: 29)), d, 'day');
  }),
  PdPreset('90d', '90 dias', () {
    final d = _day(DateTime.now());
    return _p('90d', d.subtract(const Duration(days: 89)), d, 'week');
  }),
  PdPreset('mtd', 'Mês atual', () {
    final n = DateTime.now();
    return _p(
      'mtd',
      DateTime(n.year, n.month, 1),
      DateTime(n.year, n.month + 1, 0),
      'day',
    );
  }),
  PdPreset('last-month', 'Mês passado', () {
    final n = DateTime.now();
    return _p(
      'last-month',
      DateTime(n.year, n.month - 1, 1),
      DateTime(n.year, n.month, 0),
      'day',
    );
  }),
  PdPreset('qtd', 'Trimestre', () {
    final n = DateTime.now();
    final qStart = ((n.month - 1) ~/ 3) * 3 + 1;
    return _p(
      'qtd',
      DateTime(n.year, qStart, 1),
      DateTime(n.year, qStart + 3, 0),
      'week',
    );
  }),
  PdPreset('ytd', 'Ano atual', () {
    final n = DateTime.now();
    return _p('ytd', DateTime(n.year, 1, 1), DateTime(n.year, 12, 31), 'month');
  }),
];

/// Mesma sugestão do web: até 14 dias → dia; até 90 → semana; senão mês.
String pdSuggestGranularity(DateTime from, DateTime to) {
  final days = _day(to).difference(_day(from)).inDays + 1;
  if (days <= 14) return 'day';
  if (days <= 90) return 'week';
  return 'month';
}

String pdGranularityLabel(String g) {
  switch (g) {
    case 'week':
      return 'por semana';
    case 'month':
      return 'por mês';
    case 'quarter':
      return 'por trimestre';
    case 'year':
      return 'por ano';
    default:
      return 'por dia';
  }
}

const List<(String, String)> _granularities = [
  ('day', 'Dia'),
  ('week', 'Semana'),
  ('month', 'Mês'),
];

Future<PdPeriod?> showPdPeriodSheet(BuildContext context, PdPeriod current) {
  return showModalBottomSheet<PdPeriod>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _PeriodSheet(current: current),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.current});

  final PdPeriod current;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late PdPeriod _draft = widget.current;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _draft.from, end: _draft.to),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draft = PdPeriod(
        presetId: null,
        from: _day(picked.start),
        to: _day(picked.end),
        granularity: pdSuggestGranularity(picked.start, picked.end),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final mq = MediaQuery.of(context);
    final suggested = pdSuggestGranularity(_draft.from, _draft.to);
    final rows = <List<PdPreset>>[];
    for (var i = 0; i < pdPresets.length; i += 2) {
      final end = i + 2 > pdPresets.length ? pdPresets.length : i + 2;
      rows.add(pdPresets.sublist(i, end));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(title: 'Período do painel'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(t, 'ATALHOS'),
                  for (final pair in rows) ...[
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(
                            child: i < pair.length
                                ? _presetCell(t, pair[i])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                    const PdHairline(),
                  ],
                  InkWell(
                    onTap: _pickCustom,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.calendarRange,
                            size: 17,
                            color: _draft.presetId == null ? t.accent : t.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Intervalo personalizado',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _draft.rangeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 16, color: t.muted),
                        ],
                      ),
                    ),
                  ),
                  const PdHairline(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _label(t, 'AGRUPAR A SÉRIE')),
                      if (_draft.granularity != suggested)
                        Flexible(
                          child: Text(
                            'sugerido: ${_granularities.firstWhere((g) => g.$1 == suggested).$2.toLowerCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: t.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _granularityControl(t),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + mq.padding.bottom),
            child: _ApplyButton(
              label: 'Aplicar período',
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(PdTones t, String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: t.muted,
          ),
        ),
      );

  Widget _presetCell(PdTones t, PdPreset p) {
    final active = _draft.presetId == p.id;
    return InkWell(
      onTap: () => setState(() => _draft = p.compute()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? t.text : t.muted,
                ),
              ),
            ),
            if (active) Icon(LucideIcons.check, size: 16, color: t.accent),
          ],
        ),
      ),
    );
  }

  Widget _granularityControl(PdTones t) {
    final fill = t.dark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final g in _granularities)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _draft = PdPeriod(
                    presetId: _draft.presetId,
                    from: _draft.from,
                    to: _draft.to,
                    granularity: g.$1,
                  );
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _draft.granularity == g.$1
                        ? ThemeHelpers.cardBackgroundColor(context)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _draft.granularity == g.$1
                        ? ThemeHelpers.cardShadow(context)
                        : null,
                  ),
                  child: Text(
                    g.$2,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _draft.granularity == g.$1 ? t.text : t.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Filtros avançados ───────────────────────────────────────────────────

class PdAdvancedFilters {
  final bool excludeNonCommercialTeams;
  final List<String> excludeUserIds;
  final List<String> excludeTeamIds;

  const PdAdvancedFilters({
    this.excludeNonCommercialTeams = true,
    this.excludeUserIds = const [],
    this.excludeTeamIds = const [],
  });

  /// Mesma contagem do badge do web.
  int get count =>
      (excludeNonCommercialTeams ? 1 : 0) +
      excludeUserIds.length +
      excludeTeamIds.length;

  Map<String, dynamic> toJson() => {
        'excludeNonCommercialTeams': excludeNonCommercialTeams,
        'excludeUserIds': excludeUserIds,
        'excludeTeamIds': excludeTeamIds,
      };

  factory PdAdvancedFilters.fromJson(Map<String, dynamic> j) {
    List<String> ids(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    final flag = j['excludeNonCommercialTeams'];
    return PdAdvancedFilters(
      excludeNonCommercialTeams: flag is bool ? flag : true,
      excludeUserIds: ids(j['excludeUserIds']),
      excludeTeamIds: ids(j['excludeTeamIds']),
    );
  }
}

Future<PdAdvancedFilters?> showPdAdvancedSheet(
  BuildContext context, {
  required PdAdvancedFilters current,
  required List<ProposalsPickOption> users,
  required List<ProposalsPickOption> teams,
  required bool loading,
}) {
  return showModalBottomSheet<PdAdvancedFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _AdvancedSheet(
      current: current,
      users: users,
      teams: teams,
      loading: loading,
    ),
  );
}

class _AdvancedSheet extends StatefulWidget {
  const _AdvancedSheet({
    required this.current,
    required this.users,
    required this.teams,
    required this.loading,
  });

  final PdAdvancedFilters current;
  final List<ProposalsPickOption> users;
  final List<ProposalsPickOption> teams;
  final bool loading;

  @override
  State<_AdvancedSheet> createState() => _AdvancedSheetState();
}

class _AdvancedSheetState extends State<_AdvancedSheet> {
  late bool _commercialOnly = widget.current.excludeNonCommercialTeams;
  late final Set<String> _users = {...widget.current.excludeUserIds};
  late final Set<String> _teams = {...widget.current.excludeTeamIds};
  int _tab = 0; // 0 = corretores, 1 = equipes
  String _query = '';
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final mq = MediaQuery.of(context);
    final source = _tab == 0 ? widget.users : widget.teams;
    final selected = _tab == 0 ? _users : _teams;
    final q = _norm(_query.trim());
    final options = q.isEmpty
        ? source
        : source.where((o) => _norm(o.label).contains(q)).toList();
    // Selecionados primeiro, para a exclusão ficar à vista.
    final sorted = [
      ...options.where((o) => selected.contains(o.id)),
      ...options.where((o) => !selected.contains(o.id)),
    ];
    final fill = t.dark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(title: 'Filtros avançados'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Somente equipes comerciais',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _commercialOnly
                              ? 'Equipes não comerciais ficam fora da conta.'
                              : 'Todas as equipes entram na conta.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Switch.adaptive(
                    value: _commercialOnly,
                    activeTrackColor: t.green,
                    onChanged: (v) => setState(() => _commercialOnly = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _tabButton(t, 0, 'Excluir corretores', _users.length),
                  const SizedBox(width: 18),
                  _tabButton(t, 1, 'Excluir equipes', _teams.length),
                ],
              ),
            ),
            const PdHairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 14, color: t.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: fill,
                  hintText: _tab == 0 ? 'Buscar corretor' : 'Buscar equipe',
                  hintStyle: TextStyle(color: t.muted, fontSize: 13.5),
                  prefixIcon: Icon(LucideIcons.search, size: 17, color: t.muted),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: widget.loading && source.isEmpty
                  ? ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: const [
                        SkeletonBox(height: 18, borderRadius: 6),
                        SizedBox(height: 16),
                        SkeletonBox(height: 18, borderRadius: 6),
                        SizedBox(height: 16),
                        SkeletonBox(height: 18, borderRadius: 6),
                      ],
                    )
                  : sorted.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: PdEmptyLine(
                            q.isEmpty
                                ? 'Nada disponível para excluir.'
                                : 'Nenhum resultado para "$_query".',
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: sorted.length,
                          separatorBuilder: (_, _) => const PdHairline(),
                          itemBuilder: (_, i) {
                            final o = sorted[i];
                            final on = selected.contains(o.id);
                            return InkWell(
                              onTap: () => setState(() {
                                if (on) {
                                  selected.remove(o.id);
                                } else {
                                  selected.add(o.id);
                                }
                              }),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                child: Row(
                                  children: [
                                    Icon(
                                      on
                                          ? LucideIcons.circleMinus
                                          : LucideIcons.circle,
                                      size: 18,
                                      color: on ? t.red : t.muted,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        o.label.isEmpty ? o.id : o.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: on
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: t.text,
                                          decoration: on
                                              ? TextDecoration.lineThrough
                                              : null,
                                          decorationColor: t.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const PdHairline(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                12 + (mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom),
              ),
              child: Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: t.muted),
                    onPressed: () => setState(() {
                      _commercialOnly = true;
                      _users.clear();
                      _teams.clear();
                    }),
                    child: const Text(
                      'Restaurar padrão',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ApplyButton(
                      label: 'Aplicar filtros',
                      onPressed: () => Navigator.of(context).pop(
                        PdAdvancedFilters(
                          excludeNonCommercialTeams: _commercialOnly,
                          excludeUserIds: _users.toList(),
                          excludeTeamIds: _teams.toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(PdTones t, int index, String label, int count) {
    final active = _tab == index;
    return Flexible(
      child: InkWell(
        onTap: () => setState(() {
          _tab = index;
          _query = '';
          _search.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2.5,
                color: active ? t.accent : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            count > 0 ? '$label ($count)' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: active ? t.text : t.muted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Exportação ──────────────────────────────────────────────────────────

enum PdExportKind { excel, pdf }

Future<PdExportKind?> showPdExportSheet(
  BuildContext context, {
  required bool canExport,
  required String scopeLine,
}) {
  return showModalBottomSheet<PdExportKind>(
    context: context,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final t = PdTones.of(ctx);
      Widget option(
        PdExportKind kind,
        IconData icon,
        Color tone,
        String title,
        String sub,
      ) {
        return InkWell(
          onTap: canExport ? () => Navigator.of(ctx).pop(kind) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 20, color: canExport ? tone : t.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: canExport ? t.text : t.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!canExport)
                  Icon(LucideIcons.lock, size: 15, color: t.muted)
                else
                  Icon(LucideIcons.download, size: 16, color: t.muted),
              ],
            ),
          ),
        );
      }

      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHeader(title: 'Exportar painel'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  canExport
                      ? 'Arquivo gerado no servidor com o recorte atual: $scopeLine.'
                      : 'Sua conta não tem a permissão de exportar propostas. '
                          'Peça ao administrador para liberar.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: t.muted,
                  ),
                ),
              ),
              const PdHairline(),
              option(
                PdExportKind.excel,
                LucideIcons.fileSpreadsheet,
                t.green,
                'Planilha Excel',
                'Todas as abas do painel em .xlsx',
              ),
              const PdHairline(indent: 48),
              option(
                PdExportKind.pdf,
                LucideIcons.fileText,
                t.accent,
                'Relatório em PDF',
                'Resumo pronto para enviar ou imprimir',
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

// ─── Peças dos sheets ────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: t.text,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(LucideIcons.x, size: 19, color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// Botão de aplicar: tinta do texto (neutro), nunca o vermelho da marca.
class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: t.text,
        foregroundColor: ThemeHelpers.cardBackgroundColor(context),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
