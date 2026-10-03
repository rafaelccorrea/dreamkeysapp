import 'package:flutter/material.dart';

import '../../../shared/services/sale_forms_service.dart';
import 'fichas_filters_kit.dart';
import 'sale_form_tones.dart';

/// Resultado do modal: filtros aplicados, ou `cleared` quando o usuário tocou
/// em "Limpar filtros" (a página também desliga "Apenas excluídas", como o
/// `handleClearFilters` do web).
class SaleFormsFiltersOutcome {
  final SaleFormFilters filters;
  final bool cleared;
  const SaleFormsFiltersOutcome(this.filters, {this.cleared = false});
}

/// Modal "Filtros" da lista de fichas de venda — paridade com
/// `SaleFormsFiltersDrawer.tsx` (web): status (multi), corretores (multi),
/// unidade de venda, equipes (multi), período de criação (com atalhos), data
/// da venda e ordenação. Gramática do drawer de filtros do CRM.
Future<SaleFormsFiltersOutcome?> showSaleFormsFiltersSheet(
  BuildContext context, {
  required SaleFormFilters initial,
}) {
  return showModalBottomSheet<SaleFormsFiltersOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _SaleFormsFiltersSheet(initial: initial),
  );
}

/// Recorte escolhido no modal de exportação.
class SaleFormsExportChoice {
  final SaleFormFilters filters;
  final bool deletedOnly;
  const SaleFormsExportChoice(this.filters, {this.deletedOnly = false});
}

/// Web (`SaleFormsPage.tsx` / `SaleFormsFiltersDrawer.tsx`): o filtro abre
/// com "Data da venda" = hoje (de/até) quando não há data da venda aplicada —
/// só vira filtro ao tocar em Aplicar. Cada ponta independe da outra.
({DateTime? from, DateTime? to}) saleFormsFiltroDataVendaInicial(
  SaleFormFilters f,
  DateTime agora,
) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  return (from: f.saleDateFrom ?? hoje, to: f.saleDateTo ?? hoje);
}

/// Filtros que vão para a exportação (web `ExportSaleFormsRelatorioModal`):
/// ordem por criação (mais recente primeiro), `userIds` só com
/// `sale_form:view_all` e "só excluídas" só para quem pode auditar.
SaleFormFilters saleFormsExportFilters(
  SaleFormFilters f, {
  required String search,
  required bool canViewAll,
  bool deletedOnly = false,
}) {
  final s = search.trim();
  return f.copyWith(
    search: s.isEmpty ? null : s,
    userIds: canViewAll ? f.userIds : const <String>[],
    userId: canViewAll ? f.userId : null,
    listDeletedOnly: canViewAll && deletedOnly ? true : null,
    sortBy: 'createdAt',
    sortOrder: 'DESC',
    page: 1,
  );
}

/// Modal "Exportar relatório de fichas (XLSX)" — paridade com
/// `ExportSaleFormsRelatorioModal.tsx`: começa no recorte da lista e deixa
/// ajustar busca, período de criação, data da venda, status, unidade,
/// equipes, criadores (só com `view_all`) e "só excluídas" (quem audita).
Future<SaleFormsExportChoice?> showSaleFormsExportSheet(
  BuildContext context, {
  required SaleFormFilters initial,
  required String search,
  required bool deletedOnly,
  required bool canViewAll,
}) {
  return showModalBottomSheet<SaleFormsExportChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _SaleFormsFiltersSheet(
      initial: initial,
      exportar: true,
      exportSearch: search,
      exportDeletedOnly: deletedOnly,
      canViewAll: canViewAll,
    ),
  );
}

const List<FichasSortOption> _kSortOptions = [
  FichasSortOption(
    value: 'createdAt',
    label: 'Data de criação',
    icon: Icons.schedule_rounded,
  ),
  FichasSortOption(
    value: 'formNumber',
    label: 'Número',
    icon: Icons.tag_rounded,
  ),
  FichasSortOption(
    value: 'buyerName',
    label: 'Comprador',
    icon: Icons.person_outline_rounded,
  ),
  FichasSortOption(
    value: 'sellerName',
    label: 'Vendedor',
    icon: Icons.storefront_outlined,
  ),
  FichasSortOption(
    value: 'saleUnit',
    label: 'Unidade',
    icon: Icons.apartment_rounded,
  ),
  FichasSortOption(
    value: 'saleFormType',
    label: 'Tipo',
    icon: Icons.category_outlined,
  ),
  FichasSortOption(
    value: 'status',
    label: 'Status',
    icon: Icons.flag_outlined,
  ),
  FichasSortOption(
    value: 'creatorName',
    label: 'Criado por',
    icon: Icons.badge_outlined,
  ),
];

enum _Preset { last7, last30, month, year }

class _SaleFormsFiltersSheet extends StatefulWidget {
  const _SaleFormsFiltersSheet({
    required this.initial,
    this.exportar = false,
    this.exportSearch = '',
    this.exportDeletedOnly = false,
    this.canViewAll = true,
  });

  final SaleFormFilters initial;

  /// Modo "Exportar relatório" (web `ExportSaleFormsRelatorioModal`).
  final bool exportar;
  final String exportSearch;
  final bool exportDeletedOnly;
  final bool canViewAll;

  @override
  State<_SaleFormsFiltersSheet> createState() => _SaleFormsFiltersSheetState();
}

class _SaleFormsFiltersSheetState extends State<_SaleFormsFiltersSheet> {
  late Set<SaleFormStatus> _statuses;
  late Set<String> _userIds;
  late Set<String> _teamIds;
  String? _saleUnit;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  DateTime? _saleDateFrom;
  DateTime? _saleDateTo;
  late String _sortBy;
  late String _sortOrder;
  String? _error;
  late final TextEditingController _busca;
  bool _soExcluidas = false;

  late final Future<List<FichasPickOption>> _usersFut;
  late final Future<List<FichasPickOption>> _teamsFut;
  late final Future<List<FichasPickOption>> _unitsFut;
  List<FichasPickOption>? _users;
  List<FichasPickOption>? _teams;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _statuses = f.effectiveStatuses.toSet();
    // Exportação: criadores só com `view_all` (web).
    _userIds = widget.exportar && !widget.canViewAll
        ? <String>{}
        : f.userIds.toSet();
    _teamIds = f.teamIds.toSet();
    _saleUnit = f.saleUnit;
    _dateFrom = f.dateFrom;
    _dateTo = f.dateTo;
    if (widget.exportar) {
      // O modal de exportação do web parte do recorte da lista, sem o
      // "hoje" do filtro.
      _saleDateFrom = f.saleDateFrom;
      _saleDateTo = f.saleDateTo;
    } else {
      final venda = saleFormsFiltroDataVendaInicial(f, DateTime.now());
      _saleDateFrom = venda.from;
      _saleDateTo = venda.to;
    }
    _busca = TextEditingController(text: widget.exportSearch);
    _soExcluidas = widget.exportar && widget.canViewAll && widget.exportDeletedOnly;
    _sortBy = f.sortBy;
    _sortOrder = f.sortOrder;

    _usersFut = FichasFilterCatalog.saleFormUsers();
    _teamsFut = FichasFilterCatalog.saleFormTeams();
    _unitsFut = FichasFilterCatalog.saleUnits();
    // Nomes para o resumo dos campos (os sheets de escolha usam o mesmo
    // Future — uma chamada só por abertura, como o web).
    _usersFut.then((l) {
      if (mounted) setState(() => _users = l);
    }).catchError((Object _) {});
    _teamsFut.then((l) {
      if (mounted) setState(() => _teams = l);
    }).catchError((Object _) {});
    _unitsFut.catchError((Object _) => <FichasPickOption>[]);
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  SaleFormFilters _build() {
    final unit = _saleUnit?.trim();
    return widget.initial.copyWith(
      status: null,
      statuses: [
        for (final s in SaleFormStatus.values)
          if (_statuses.contains(s)) s,
      ],
      userIds: _userIds.toList(),
      teamIds: _teamIds.toList(),
      saleUnit: (unit == null || unit.isEmpty) ? null : unit,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      saleDateFrom: _saleDateFrom,
      saleDateTo: _saleDateTo,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
      page: 1,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _applyPreset(_Preset p) {
    final end = _day(DateTime.now());
    late DateTime start;
    switch (p) {
      case _Preset.last7:
        start = end.subtract(const Duration(days: 7));
        break;
      case _Preset.last30:
        start = end.subtract(const Duration(days: 30));
        break;
      case _Preset.month:
        start = DateTime(end.year, end.month, 1);
        break;
      case _Preset.year:
        start = DateTime(end.year, 1, 1);
        break;
    }
    setState(() {
      _dateFrom = start;
      _dateTo = end;
      _error = null;
    });
  }

  bool _isPreset(_Preset p) {
    if (_dateFrom == null || _dateTo == null) return false;
    final end = _day(DateTime.now());
    if (_day(_dateTo!) != end) return false;
    final from = _day(_dateFrom!);
    switch (p) {
      case _Preset.last7:
        return from == end.subtract(const Duration(days: 7));
      case _Preset.last30:
        return from == end.subtract(const Duration(days: 30));
      case _Preset.month:
        return from == DateTime(end.year, end.month, 1);
      case _Preset.year:
        return from == DateTime(end.year, 1, 1);
    }
  }

  void _apply() {
    if (_dateFrom != null &&
        _dateTo != null &&
        _day(_dateFrom!).isAfter(_day(_dateTo!))) {
      setState(
        () => _error = 'A data inicial não pode ser posterior à data final.',
      );
      return;
    }
    if (_saleDateFrom != null &&
        _saleDateTo != null &&
        _day(_saleDateFrom!).isAfter(_day(_saleDateTo!))) {
      setState(
        () => _error =
            'A data da venda inicial não pode ser posterior à data final.',
      );
      return;
    }
    if (widget.exportar) {
      Navigator.of(context).pop(
        SaleFormsExportChoice(
          saleFormsExportFilters(
            _build(),
            search: _busca.text,
            canViewAll: widget.canViewAll,
            deletedOnly: _soExcluidas,
          ),
          deletedOnly: widget.canViewAll && _soExcluidas,
        ),
      );
      return;
    }
    Navigator.of(context).pop(SaleFormsFiltersOutcome(_build()));
  }

  void _clear() {
    if (widget.exportar) {
      // Exportação: limpa os campos aqui mesmo (o modal continua aberto).
      setState(() {
        _busca.clear();
        _statuses = <SaleFormStatus>{};
        _userIds = <String>{};
        _teamIds = <String>{};
        _saleUnit = null;
        _dateFrom = null;
        _dateTo = null;
        _saleDateFrom = null;
        _saleDateTo = null;
        _soExcluidas = false;
        _error = null;
      });
      return;
    }
    Navigator.of(context).pop(
      SaleFormsFiltersOutcome(
        widget.initial.withoutListFilters(),
        cleared: true,
      ),
    );
  }

  Future<void> _pickUsers(Color accent) async {
    final res = await showFichasPickSheet(
      context,
      eyebrow: 'Corretores',
      title: 'Fichas criadas por',
      accent: accent,
      options: _usersFut,
      selected: _userIds,
      searchHint: 'Buscar corretor por nome ou e-mail…',
      emptyMessage: 'Nenhum corretor encontrado.',
    );
    if (res != null && mounted) setState(() => _userIds = res);
  }

  Future<void> _pickTeams(Color accent) async {
    final res = await showFichasPickSheet(
      context,
      eyebrow: 'Equipes',
      title: 'Equipes vinculadas às fichas',
      accent: accent,
      options: _teamsFut,
      selected: _teamIds,
      searchHint: 'Buscar equipe…',
      emptyMessage: 'Nenhuma equipe disponível.',
      icon: Icons.groups_outlined,
    );
    if (res != null && mounted) setState(() => _teamIds = res);
  }

  Future<void> _pickUnit(Color accent) async {
    final cur = _saleUnit?.trim();
    final res = await showFichasPickSheet(
      context,
      eyebrow: 'Unidade',
      title: 'Unidade de venda',
      accent: accent,
      options: _unitsFut,
      selected: (cur == null || cur.isEmpty) ? <String>{} : {cur},
      multi: false,
      allLabel: 'Todas',
      searchHint: 'Buscar unidade…',
      emptyMessage: 'Nenhuma unidade configurada.',
      icon: Icons.storefront_outlined,
    );
    if (res != null && mounted) {
      setState(() => _saleUnit = res.isEmpty ? null : res.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cStatus = FichasFilterTones.amber(context);
    final cUsers = FichasFilterTones.green(context);
    final cUnit = FichasFilterTones.teal(context);
    final cTeams = FichasFilterTones.purple(context);
    final cPeriod = FichasFilterTones.blue(context);
    final cSale = FichasFilterTones.rose(context);
    final cSort = FichasFilterTones.slate(context);
    final activeCount = _build().drawerFilterCount;
    final unit = _saleUnit?.trim();

    String? plural(int n, String one, String many) =>
        n == 0 ? null : '$n ${n == 1 ? one : many}';

    final exportar = widget.exportar;
    final mostraCorretores = !exportar || widget.canViewAll;
    return FichasSheetShell(
      header: FichasFilterSheetHeader(
        title: exportar
            ? 'Exportar relatório de fichas (XLSX)'
            : 'Filtros de fichas de venda',
        activeCount: activeCount,
      ),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (exportar) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                widget.canViewAll
                    ? 'Com permissão de ver todas as fichas, você pode '
                        'restringir por criador, equipe (membros) e período. '
                        'Gestores sem essa permissão exportam apenas o escopo '
                        'já aplicado pela regra de acesso.'
                    : 'Sem «ver todas», a planilha segue a mesma regra da '
                        'lista (suas fichas, vínculos e hierarquia). Você '
                        'ainda pode filtrar por período, status, busca e '
                        'unidade.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.4,
                    ),
              ),
            ),
            FichasFilterSection(
              accent: cStatus,
              label: 'Buscar ficha (comprador, nº, imóvel…)',
              child: TextField(
                controller: _busca,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  hintText: 'Nº, comprador, vendedor ou imóvel',
                ),
              ),
            ),
          ],
          FichasFilterSection(
            first: !exportar,
            accent: cStatus,
            label: 'Status',
            hint: 'Marque um ou mais.',
            trailing: plural(_statuses.length, 'selecionado', 'selecionados'),
            child: FichasChipGrid(
              children: [
                for (final s in SaleFormStatus.values)
                  FichasChoiceChip(
                    // Mesmos rótulos e cores dos atalhos do topo da lista
                    // (cada status na sua cor, com o ponto).
                    label: s.shortLabel,
                    selected: _statuses.contains(s),
                    accent: SaleFormTom.doStatus(context, s).texto,
                    dot: true,
                    onTap: () => setState(() {
                      if (!_statuses.remove(s)) _statuses.add(s);
                    }),
                  ),
              ],
            ),
          ),
          if (mostraCorretores)
          FichasFilterSection(
            accent: cUsers,
            label: 'Corretores',
            hint: 'Quem criou a ficha.',
            trailing: plural(_userIds.length, 'selecionado', 'selecionados'),
            child: FichasFilterField(
              icon: Icons.person_outline_rounded,
              accent: cUsers,
              caption: 'Corretores',
              placeholder: 'Todos',
              value: fichasSelectionSummary(
                _userIds,
                _users,
                noun: 'corretor',
                nounPlural: 'corretores',
              ),
              onTap: () => _pickUsers(cUsers),
              onClear: () => setState(() => _userIds = <String>{}),
            ),
          ),
          FichasFilterSection(
            accent: cUnit,
            label: 'Unidade',
            child: FichasFilterField(
              icon: Icons.storefront_outlined,
              accent: cUnit,
              caption: 'Unidade de venda',
              placeholder: 'Todas',
              value: (unit == null || unit.isEmpty) ? null : unit,
              onTap: () => _pickUnit(cUnit),
              onClear: () => setState(() => _saleUnit = null),
            ),
          ),
          FichasFilterSection(
            accent: cTeams,
            label: 'Equipes',
            hint: 'Equipes vinculadas às fichas.',
            trailing: plural(_teamIds.length, 'selecionada', 'selecionadas'),
            child: FichasFilterField(
              icon: Icons.groups_outlined,
              accent: cTeams,
              caption: 'Equipes',
              placeholder: 'Todas',
              value: fichasSelectionSummary(
                _teamIds,
                _teams,
                noun: 'equipe',
                nounPlural: 'equipes',
              ),
              onTap: () => _pickTeams(cTeams),
              onClear: () => setState(() => _teamIds = <String>{}),
            ),
          ),
          FichasFilterSection(
            accent: cPeriod,
            label: 'Período',
            hint: 'Pela data de criação da ficha.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FichasChipGrid(
                  children: [
                    FichasChoiceChip(
                      label: 'Últimos 7 dias',
                      selected: _isPreset(_Preset.last7),
                      accent: cPeriod,
                      onTap: () => _applyPreset(_Preset.last7),
                    ),
                    FichasChoiceChip(
                      label: 'Últimos 30 dias',
                      selected: _isPreset(_Preset.last30),
                      accent: cPeriod,
                      onTap: () => _applyPreset(_Preset.last30),
                    ),
                    FichasChoiceChip(
                      label: 'Mês atual',
                      selected: _isPreset(_Preset.month),
                      accent: cPeriod,
                      onTap: () => _applyPreset(_Preset.month),
                    ),
                    FichasChoiceChip(
                      label: 'Ano até hoje',
                      selected: _isPreset(_Preset.year),
                      accent: cPeriod,
                      onTap: () => _applyPreset(_Preset.year),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FichasDateRangeField(
                  accent: cPeriod,
                  from: _dateFrom,
                  to: _dateTo,
                  onChanged: (a, b) => setState(() {
                    _dateFrom = a;
                    _dateTo = b;
                    _error = null;
                  }),
                ),
              ],
            ),
          ),
          FichasFilterSection(
            accent: cSale,
            label: 'Data da venda',
            hint: 'Data da venda, não a de criação da ficha.',
            child: FichasDateRangeField(
              accent: cSale,
              from: _saleDateFrom,
              to: _saleDateTo,
              fromCaption: 'Venda — data inicial',
              toCaption: 'Venda — data final',
              icon: Icons.event_available_outlined,
              onChanged: (a, b) => setState(() {
                _saleDateFrom = a;
                _saleDateTo = b;
                _error = null;
              }),
            ),
          ),
          // Exportação: sempre por criação, mais recente primeiro (web).
          if (exportar && widget.canViewAll)
            FichasFilterSection(
              accent: cSort,
              label: 'Excluídas',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _soExcluidas,
                onChanged: (v) => setState(() => _soExcluidas = v),
                title: const Text(
                  'Somente fichas excluídas (com motivo registrado)',
                ),
              ),
            ),
          if (!exportar)
          FichasFilterSection(
            accent: cSort,
            label: 'Ordenação',
            hint: 'Decrescente: mais recente, Z→A, maior. '
                'Aplicada junto com os filtros.',
            child: FichasSortControl(
              accent: cSort,
              options: _kSortOptions,
              sortBy: _sortBy,
              sortOrder: _sortOrder,
              title: 'Ordem das fichas',
              onChanged: (by, order) => setState(() {
                _sortBy = by;
                _sortOrder = order;
              }),
            ),
          ),
        ],
      ),
      footer: FichasFilterFooter(
        activeCount: activeCount,
        error: _error,
        onApply: _apply,
        onClear: _clear,
        applyLabel: exportar ? 'Exportar' : 'Aplicar',
        clearLabel: exportar ? 'Limpar' : 'Limpar filtros',
      ),
    );
  }
}
