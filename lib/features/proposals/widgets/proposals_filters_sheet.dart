import 'package:flutter/material.dart';

import '../../../shared/services/purchase_proposals_service.dart';
import '../../sale_forms/widgets/fichas_filters_kit.dart';

/// Resultado do modal: filtros aplicados, ou `cleared` quando o usuário tocou
/// em "Limpar filtros" (a página também desliga "Apenas excluídas", como o
/// `clearDrawerFilters` do web).
class ProposalsFiltersOutcome {
  final ProposalFilters filters;
  final bool cleared;
  const ProposalsFiltersOutcome(this.filters, {this.cleared = false});
}

/// Modal "Filtros" da lista de fichas de proposta — paridade com o drawer de
/// `PurchaseProposalsPage.tsx` (web): status, etapa, unidade de venda,
/// período de criação, autor (só com `proposal:view_all`, como no web — o
/// back ignora o autor sem essa permissão) e ordenação.
Future<ProposalsFiltersOutcome?> showProposalsFiltersSheet(
  BuildContext context, {
  required ProposalFilters initial,
  required bool canViewAll,
}) {
  return showModalBottomSheet<ProposalsFiltersOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) =>
        _ProposalsFiltersSheet(initial: initial, canViewAll: canViewAll),
  );
}

const List<FichasSortOption> _kSortOptions = [
  FichasSortOption(
    value: 'createdAt',
    label: 'Data de criação',
    icon: Icons.schedule_rounded,
  ),
  FichasSortOption(
    value: 'proposalNumber',
    label: 'Número',
    icon: Icons.tag_rounded,
  ),
  FichasSortOption(
    value: 'status',
    label: 'Status',
    icon: Icons.flag_outlined,
  ),
  FichasSortOption(
    value: 'proponentName',
    label: 'Comprador (proponente)',
    icon: Icons.person_outline_rounded,
  ),
  FichasSortOption(
    value: 'proposedPrice',
    label: 'Valor proposto',
    icon: Icons.payments_outlined,
  ),
  FichasSortOption(
    value: 'validityDays',
    label: 'Validade (dias)',
    icon: Icons.hourglass_empty_rounded,
  ),
  FichasSortOption(
    value: 'creatorName',
    label: 'Criado por (nome)',
    icon: Icons.badge_outlined,
  ),
];

String _etapaChip(ProposalEtapa e) {
  switch (e) {
    case ProposalEtapa.comprador:
      return '1 · Comprador';
    case ProposalEtapa.proprietario:
      return '2 · Proprietário';
    case ProposalEtapa.corretor:
      return '3 · Corretor';
  }
}

class _ProposalsFiltersSheet extends StatefulWidget {
  const _ProposalsFiltersSheet({
    required this.initial,
    required this.canViewAll,
  });

  final ProposalFilters initial;
  final bool canViewAll;

  @override
  State<_ProposalsFiltersSheet> createState() => _ProposalsFiltersSheetState();
}

class _ProposalsFiltersSheetState extends State<_ProposalsFiltersSheet> {
  ProposalStatus? _status;
  ProposalEtapa? _etapa;
  String? _saleUnit;
  String? _userId;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  late String _sortBy;
  late String _sortOrder;
  String? _error;

  late final Future<List<FichasPickOption>> _unitsFut;
  Future<List<FichasPickOption>>? _membersFut;
  List<FichasPickOption>? _members;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _status = f.status;
    _etapa = f.etapa;
    _saleUnit = f.saleUnit;
    _userId = widget.canViewAll ? f.userId : null;
    _dateFrom = f.dateFrom;
    _dateTo = f.dateTo;
    _sortBy = f.sortBy;
    _sortOrder = f.sortOrder;

    _unitsFut = FichasFilterCatalog.saleUnits();
    _unitsFut.catchError((Object _) => <FichasPickOption>[]);
    if (widget.canViewAll) {
      final fut = FichasFilterCatalog.companyMembers();
      _membersFut = fut;
      fut.then((l) {
        if (mounted) setState(() => _members = l);
      }).catchError((Object _) {});
    }
  }

  ProposalFilters _build() {
    final unit = _saleUnit?.trim();
    return widget.initial.copyWith(
      status: _status,
      etapa: _etapa,
      saleUnit: (unit == null || unit.isEmpty) ? null : unit,
      userId: widget.canViewAll ? _userId : null,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
      page: 1,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _apply() {
    if (_dateFrom != null &&
        _dateTo != null &&
        _day(_dateFrom!).isAfter(_day(_dateTo!))) {
      setState(
        () => _error = 'A data inicial não pode ser posterior à data final.',
      );
      return;
    }
    Navigator.of(context).pop(ProposalsFiltersOutcome(_build()));
  }

  void _clear() {
    Navigator.of(context).pop(
      ProposalsFiltersOutcome(
        widget.initial.withoutListFilters(),
        cleared: true,
      ),
    );
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

  Future<void> _pickAuthor(Color accent) async {
    final fut = _membersFut;
    if (fut == null) return;
    final res = await showFichasPickSheet(
      context,
      eyebrow: 'Autor',
      title: 'Quem criou a ficha',
      accent: accent,
      options: fut,
      selected: _userId == null ? <String>{} : {_userId!},
      multi: false,
      allLabel: 'Todos',
      searchHint: 'Buscar por nome ou e-mail…',
      emptyMessage: 'Nenhum usuário encontrado.',
    );
    if (res != null && mounted) {
      setState(() => _userId = res.isEmpty ? null : res.first);
    }
  }

  String? _authorName() {
    final id = _userId;
    if (id == null || id.isEmpty) return null;
    for (final m in _members ?? const <FichasPickOption>[]) {
      if (m.id == id) return m.label;
    }
    return 'Usuário selecionado';
  }

  @override
  Widget build(BuildContext context) {
    final cStatus = FichasFilterTones.green(context);
    final cEtapa = FichasFilterTones.purple(context);
    final cUnit = FichasFilterTones.teal(context);
    final cPeriod = FichasFilterTones.amber(context);
    final cAuthor = FichasFilterTones.sky(context);
    final cSort = FichasFilterTones.slate(context);
    final activeCount = _build().drawerFilterCount;
    final unit = _saleUnit?.trim();

    return FichasSheetShell(
      header: FichasFilterSheetHeader(
        title: 'Filtros de propostas',
        activeCount: activeCount,
      ),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          FichasFilterSection(
            first: true,
            accent: cStatus,
            label: 'Status',
            hint: 'Situação da proposta.',
            child: FichasChipGrid(
              children: [
                FichasChoiceChip(
                  label: 'Todos',
                  selected: _status == null,
                  accent: cStatus,
                  onTap: () => setState(() => _status = null),
                ),
                for (final s in ProposalStatus.values)
                  FichasChoiceChip(
                    label: s.label,
                    selected: _status == s,
                    accent: cStatus,
                    onTap: () => setState(() => _status = s),
                  ),
              ],
            ),
          ),
          FichasFilterSection(
            accent: cEtapa,
            label: 'Etapa',
            hint: 'Etapa de assinatura em que a proposta está.',
            child: FichasChipGrid(
              children: [
                FichasChoiceChip(
                  label: 'Todas',
                  selected: _etapa == null,
                  accent: cEtapa,
                  onTap: () => setState(() => _etapa = null),
                ),
                for (final e in ProposalEtapa.values)
                  FichasChoiceChip(
                    label: _etapaChip(e),
                    selected: _etapa == e,
                    accent: cEtapa,
                    onTap: () => setState(() => _etapa = e),
                  ),
              ],
            ),
          ),
          FichasFilterSection(
            accent: cUnit,
            label: 'Unidade',
            hint: 'Unidade de venda registrada na ficha.',
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
            accent: cPeriod,
            label: 'Período',
            hint: 'Pela data de criação.',
            child: FichasDateRangeField(
              accent: cPeriod,
              from: _dateFrom,
              to: _dateTo,
              fromCaption: 'De',
              toCaption: 'Até',
              onChanged: (a, b) => setState(() {
                _dateFrom = a;
                _dateTo = b;
                _error = null;
              }),
            ),
          ),
          if (widget.canViewAll)
            FichasFilterSection(
              accent: cAuthor,
              label: 'Autor',
              hint: 'Quem criou a ficha.',
              child: FichasFilterField(
                icon: Icons.person_outline_rounded,
                accent: cAuthor,
                caption: 'Criado por',
                placeholder: 'Todos',
                value: _authorName(),
                onTap: () => _pickAuthor(cAuthor),
                onClear: () => setState(() => _userId = null),
              ),
            ),
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
              title: 'Ordem das propostas',
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
      ),
    );
  }
}
