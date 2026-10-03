import 'package:flutter/material.dart';

import '../../../shared/services/sale_form_overview_service.dart';
import '../sale_forms_overview_filters.dart';
import 'fichas_filters_kit.dart';

/// Filtros do painel de Fichas de Venda — `OverviewFiltersBar` do web em
/// formato de folha: período (datas + granularidade), corretor, equipe,
/// unidade e status. Os campos de corretor/equipe/unidade só aparecem quando
/// o escopo do papel permite (mesma regra do web).
///
/// Devolve o novo estado ao tocar em "Aplicar"; `null` = fechou sem aplicar.
Future<SaleFormsOverviewFilters?> showSaleFormsOverviewFiltersSheet(
  BuildContext context, {
  required SaleFormsOverviewFilters value,
  required List<SaleFormsOverviewPickOption> users,
  required List<SaleFormsOverviewPickOption> teams,
  required List<SaleFormsOverviewPickOption> units,
  required SaleFormsOverviewScopeUi scope,
}) {
  return showModalBottomSheet<SaleFormsOverviewFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _OverviewFiltersSheet(
      value: value,
      users: users,
      teams: teams,
      units: units,
      scope: scope,
    ),
  );
}

class _OverviewFiltersSheet extends StatefulWidget {
  const _OverviewFiltersSheet({
    required this.value,
    required this.users,
    required this.teams,
    required this.units,
    required this.scope,
  });

  final SaleFormsOverviewFilters value;
  final List<SaleFormsOverviewPickOption> users;
  final List<SaleFormsOverviewPickOption> teams;
  final List<SaleFormsOverviewPickOption> units;
  final SaleFormsOverviewScopeUi scope;

  @override
  State<_OverviewFiltersSheet> createState() => _OverviewFiltersSheetState();
}

class _OverviewFiltersSheetState extends State<_OverviewFiltersSheet> {
  late SaleFormsOverviewFilters _f = widget.value;

  static const _grans = [
    (id: 'day', label: 'Dia'),
    (id: 'week', label: 'Semana'),
    (id: 'month', label: 'Mês'),
  ];

  List<FichasPickOption> _pick(List<SaleFormsOverviewPickOption> l) => [
    for (final o in l) FichasPickOption(id: o.id, label: o.label),
  ];

  void _setDates(DateTime? from, DateTime? to) {
    // Sem "limpar" (o web usa `allowClear={false}`) e com início ≤ fim.
    var a = from ?? overviewFromYmd(_f.dateFrom);
    var b = to ?? overviewFromYmd(_f.dateTo);
    if (a != null && b != null && a.isAfter(b)) {
      if (from != null && from != overviewFromYmd(_f.dateFrom)) {
        b = a;
      } else {
        a = b;
      }
    }
    setState(() {
      _f = coherentOverviewFilters(
        _f.copyWith(
          dateFrom: a == null ? null : overviewYmd(a),
          dateTo: b == null ? null : overviewYmd(b),
        ),
      );
    });
  }

  Future<void> _openPick({
    required String eyebrow,
    required String title,
    required Color accent,
    required IconData icon,
    required List<SaleFormsOverviewPickOption> options,
    required List<String> selected,
    required void Function(List<String>) onDone,
  }) async {
    final out = await showFichasPickSheet(
      context,
      eyebrow: eyebrow,
      title: title,
      accent: accent,
      icon: icon,
      options: Future.value(_pick(options)),
      selected: selected.toSet(),
    );
    if (out == null || !mounted) return;
    setState(() => onDone(out.toList()));
  }

  String? _summary(
    List<String> ids,
    List<SaleFormsOverviewPickOption> options,
    String noun,
    String plural,
  ) => fichasSelectionSummary(
    ids.toSet(),
    _pick(options),
    noun: noun,
    nounPlural: plural,
  );

  @override
  Widget build(BuildContext context) {
    final brand = FichasFilterTones.brand(context);
    final blue = FichasFilterTones.blue(context);
    final teal = FichasFilterTones.teal(context);
    final purple = FichasFilterTones.purple(context);
    final amber = FichasFilterTones.amber(context);
    final now = DateTime.now();
    final presetId = resolveOverviewPresetId(_f, now);
    return FichasSheetShell(
      header: FichasFilterSheetHeader(
        title: 'Filtros do painel',
        activeCount: _f.dimensionCount,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FichasFilterSection(
              first: true,
              accent: brand,
              label: 'Período',
              trailing: formatOverviewRangeLabel(_f),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in kOverviewPresets)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: presetId == p.id,
                          showCheckmark: false,
                          onSelected: (_) => setState(
                            () => _f = applyOverviewPreset(_f, p, now),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FichasDateRangeField(
                    accent: brand,
                    from: overviewFromYmd(_f.dateFrom),
                    to: overviewFromYmd(_f.dateTo),
                    onChanged: _setDates,
                  ),
                ],
              ),
            ),
            FichasFilterSection(
              accent: blue,
              label: 'Granularidade do gráfico',
              hint: 'Ajustada ao tamanho do período, como no sistema web.',
              child: FichasChipGrid(
                children: [
                  for (final g in _grans)
                    FichasChoiceChip(
                      label: g.label,
                      selected: _f.granularity == g.id,
                      accent: blue,
                      onTap: () => setState(() {
                        _f = coherentOverviewFilters(
                          _f.copyWith(granularity: g.id),
                        );
                      }),
                    ),
                ],
              ),
            ),
            if (widget.scope.showUserFilter)
              FichasFilterSection(
                accent: teal,
                label: 'Corretor',
                child: FichasFilterField(
                  icon: Icons.person_outline_rounded,
                  accent: teal,
                  caption: 'Corretores',
                  placeholder: 'Todos os corretores',
                  value: _summary(
                    _f.userIds,
                    widget.users,
                    'corretor',
                    'corretores',
                  ),
                  onClear: () =>
                      setState(() => _f = _f.copyWith(userIds: const [])),
                  onTap: () => _openPick(
                    eyebrow: 'Corretor',
                    title: 'Filtrar por corretor',
                    accent: teal,
                    icon: Icons.person_outline_rounded,
                    options: widget.users,
                    selected: _f.userIds,
                    onDone: (ids) => _f = _f.copyWith(userIds: ids),
                  ),
                ),
              ),
            if (widget.scope.showTeamFilter)
              FichasFilterSection(
                accent: purple,
                label: 'Equipe',
                child: FichasFilterField(
                  icon: Icons.groups_outlined,
                  accent: purple,
                  caption: 'Equipes',
                  placeholder: 'Todas as equipes',
                  value: _summary(
                    _f.teamIds,
                    widget.teams,
                    'equipe',
                    'equipes',
                  ),
                  onClear: () =>
                      setState(() => _f = _f.copyWith(teamIds: const [])),
                  onTap: () => _openPick(
                    eyebrow: 'Equipe',
                    title: 'Filtrar por equipe',
                    accent: purple,
                    icon: Icons.groups_outlined,
                    options: widget.teams,
                    selected: _f.teamIds,
                    onDone: (ids) => _f = _f.copyWith(teamIds: ids),
                  ),
                ),
              ),
            if (widget.scope.showUnitFilter)
              FichasFilterSection(
                accent: amber,
                label: 'Unidade',
                child: FichasFilterField(
                  icon: Icons.storefront_outlined,
                  accent: amber,
                  caption: 'Unidades',
                  placeholder: 'Todas as unidades',
                  value: _summary(
                    _f.unitIds,
                    widget.units,
                    'unidade',
                    'unidades',
                  ),
                  onClear: () =>
                      setState(() => _f = _f.copyWith(unitIds: const [])),
                  onTap: () => _openPick(
                    eyebrow: 'Unidade',
                    title: 'Filtrar por unidade',
                    accent: amber,
                    icon: Icons.storefront_outlined,
                    options: widget.units,
                    selected: _f.unitIds,
                    onDone: (ids) => _f = _f.copyWith(unitIds: ids),
                  ),
                ),
              ),
            FichasFilterSection(
              accent: FichasFilterTones.green(context),
              label: 'Status',
              hint: 'Sem seleção = todos os status.',
              child: FichasChipGrid(
                children: [
                  for (final o in kOverviewStatusOptions)
                    FichasChoiceChip(
                      label: o.label,
                      selected: _f.status.contains(o.value),
                      accent: FichasFilterTones.green(context),
                      onTap: () => setState(() {
                        final next = [..._f.status];
                        if (!next.remove(o.value)) next.add(o.value);
                        _f = _f.copyWith(status: next);
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: FichasFilterFooter(
        activeCount: _f.dimensionCount,
        clearLabel: 'Limpar',
        // "Limpar" do web volta tudo ao mês corrente (`onClear`).
        onClear: () => setState(() => _f = overviewCurrentMonthDefault(now)),
        onApply: () => Navigator.of(context).pop(_f),
      ),
    );
  }
}
