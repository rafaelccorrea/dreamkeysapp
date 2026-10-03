/// Regras do painel de Fichas de Venda — porte de `overviewFilterUtils.ts` e
/// das funções puras de `SaleFormsDashboardPage.tsx` (web): período padrão
/// (mês corrente), presets, granularidade coerente, escopo efetivo, filtros
/// guardados no aparelho e o recorte do drill-down (`FichasListDrawer`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/services/module_access_service.dart';
import '../../shared/services/sale_form_overview_service.dart';
import '../../shared/services/sale_forms_service.dart';
import '../../shared/services/secure_storage_service.dart';

// ─── Datas ────────────────────────────────────────────────────────────────

String overviewYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `fromYmd` do web: só `YYYY-MM-DD` válido, como dia local.
DateTime? overviewFromYmd(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (y == 0 || mo == 0 || d == 0) return null;
  return DateTime(y, mo, d);
}

int _diffDaysInclusive(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  final n = b.difference(a).inDays + 1;
  return n < 1 ? 1 : n;
}

/// Granularidade coerente com o intervalo (`coalesceGranularityForRange`).
String coalesceOverviewGranularity(DateTime from, DateTime to, String desired) {
  final days = _diffDaysInclusive(from, to);
  if (desired == 'day') {
    if (days > 365) return 'month';
    if (days > 90) return 'week';
    return 'day';
  }
  if (desired == 'week') {
    if (days > 730) return 'month';
    if (days <= 7) return 'day';
    return 'week';
  }
  if (days <= 14) return 'day';
  if (days <= 45) return 'week';
  return 'month';
}

/// Aplica a granularidade coerente quando há as duas datas.
SaleFormsOverviewFilters coherentOverviewFilters(SaleFormsOverviewFilters f) {
  final from = overviewFromYmd(f.dateFrom);
  final to = overviewFromYmd(f.dateTo);
  if (from == null || to == null) return f;
  return f.copyWith(
    granularity: coalesceOverviewGranularity(from, to, f.granularity),
  );
}

// ─── Período padrão e presets ─────────────────────────────────────────────

/// `currentMonthDefault` do web: 1º ao último dia do mês, por dia, sem
/// recortes.
SaleFormsOverviewFilters overviewCurrentMonthDefault(DateTime now) =>
    SaleFormsOverviewFilters(
      dateFrom: overviewYmd(DateTime(now.year, now.month, 1)),
      dateTo: overviewYmd(DateTime(now.year, now.month + 1, 0)),
      granularity: 'day',
    );

class OverviewPreset {
  final String id;
  final String label;
  final ({DateTime from, DateTime to, String granularity}) Function(
    DateTime now,
  )
  compute;

  const OverviewPreset(this.id, this.label, this.compute);
}

/// `OVERVIEW_PRESETS` do web (mesmos ids, rótulos e granularidades).
final List<OverviewPreset> kOverviewPresets = [
  OverviewPreset('today', 'Hoje', (now) {
    final d = DateTime(now.year, now.month, now.day);
    return (from: d, to: d, granularity: 'day');
  }),
  OverviewPreset('7d', '7 dias', (now) {
    final d = DateTime(now.year, now.month, now.day);
    return (
      from: DateTime(d.year, d.month, d.day - 6),
      to: d,
      granularity: 'day',
    );
  }),
  OverviewPreset('mtd', 'Mês atual', (now) {
    return (
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month + 1, 0),
      granularity: 'day',
    );
  }),
  OverviewPreset('last-month', 'Mês passado', (now) {
    return (
      from: DateTime(now.year, now.month - 1, 1),
      to: DateTime(now.year, now.month, 0),
      granularity: 'day',
    );
  }),
  OverviewPreset('ytd', 'Ano', (now) {
    return (
      from: DateTime(now.year, 1, 1),
      to: DateTime(now.year, 12, 31),
      granularity: 'month',
    );
  }),
];

/// Aplica um preset mantendo os recortes (corretor, equipe, unidade, status).
SaleFormsOverviewFilters applyOverviewPreset(
  SaleFormsOverviewFilters f,
  OverviewPreset preset,
  DateTime now,
) {
  final r = preset.compute(now);
  return f.copyWith(
    dateFrom: overviewYmd(r.from),
    dateTo: overviewYmd(r.to),
    granularity: r.granularity,
  );
}

/// `resolveActivePresetId`: datas e granularidade batem com algum preset.
String? resolveOverviewPresetId(SaleFormsOverviewFilters f, DateTime now) {
  if (f.dateFrom == null || f.dateTo == null) return null;
  for (final p in kOverviewPresets) {
    final r = p.compute(now);
    if (f.dateFrom == overviewYmd(r.from) &&
        f.dateTo == overviewYmd(r.to) &&
        f.granularity == r.granularity) {
      return p.id;
    }
  }
  return null;
}

const List<String> _kMonthsPt = [
  'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', //
  'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
];

/// `formatRangeLabel` do web: "Out/2026", "1–15 Out/2026", …
String? formatOverviewRangeLabel(SaleFormsOverviewFilters f) {
  final from = overviewFromYmd(f.dateFrom);
  final to = overviewFromYmd(f.dateTo);
  if (from == null || to == null) return null;
  final mf = _kMonthsPt[from.month - 1];
  final mt = _kMonthsPt[to.month - 1];
  final sameYear = from.year == to.year;
  final sameMonth = sameYear && from.month == to.month;
  if (sameMonth) {
    final last = DateTime(from.year, from.month + 1, 0).day;
    if (from.day == 1 && to.day == last) return '$mf/${from.year}';
    return '${from.day}–${to.day} $mf/${from.year}';
  }
  if (sameYear) {
    return '${from.day} $mf – ${to.day} $mt/${to.year}';
  }
  return '${from.day}/$mf/${from.year} – ${to.day}/$mt/${to.year}';
}

// ─── Status do painel ─────────────────────────────────────────────────────

/// Status que o filtro do painel oferece (sem "canceladas", como no web).
const List<({String value, String label})> kOverviewStatusOptions = [
  (value: 'finalized', label: 'Finalizadas'),
  (value: 'waiting_for_signature', label: 'Aguardando assinatura'),
  (value: 'processing', label: 'Em processamento'),
];

SaleFormStatus? overviewStatusFromKey(String key) {
  for (final s in SaleFormStatus.values) {
    if (s.apiValue == key) return s;
  }
  return null;
}

/// `resolvePanelMetricLabels` do web.
({
  String vgvTitle,
  String vgcTitle,
  String rankingVgvSubtitle,
  bool showConversion,
  bool valuesScoped,
})
resolveOverviewMetricLabels(List<String> status) {
  if (status.isEmpty) {
    return (
      vgvTitle: 'VGV finalizado no período',
      vgcTitle: 'VGC finalizado',
      rankingVgvSubtitle: 'Ordenado por VGV finalizado',
      showConversion: true,
      valuesScoped: false,
    );
  }
  if (status.length == 1) {
    final label =
        kOverviewStatusOptions
            .where((o) => o.value == status.first)
            .map((o) => o.label)
            .firstOrNull ??
        status.first;
    return (
      vgvTitle: 'VGV — $label',
      vgcTitle: 'VGC — $label',
      rankingVgvSubtitle: 'Ordenado por VGV (${label.toLowerCase()})',
      showConversion: status.first == 'finalized',
      valuesScoped: true,
    );
  }
  return (
    vgvTitle: 'VGV no recorte filtrado',
    vgcTitle: 'VGC no recorte filtrado',
    rankingVgvSubtitle: 'Ordenado por VGV do recorte',
    showConversion: status.contains('finalized'),
    valuesScoped: true,
  );
}

// ─── Escopo ───────────────────────────────────────────────────────────────

/// `resolveEffectiveScopeUi`: travas do papel + quantidade de opções.
SaleFormsOverviewScopeUi resolveOverviewEffectiveScope(
  SaleFormsOverviewScopeUi ui, {
  required int users,
  required int teams,
  required int units,
}) {
  switch (ui.scopeTier) {
    case 'all':
      return ui.copyWith(
        showUserFilter: ui.showUserFilter && users > 1,
        showTeamFilter: ui.showTeamFilter && teams > 1,
        showUnitFilter: ui.showUnitFilter && units > 1,
        showBrokerRanking: ui.showBrokerRanking && users > 1,
        showTeamRanking: ui.showTeamRanking && teams > 1,
        showUnitSection: ui.showUnitSection && units > 0,
      );
    case 'unit':
      return ui.copyWith(
        showUserFilter: ui.showUserFilter && users > 1,
        showTeamFilter: ui.showTeamFilter && teams > 1,
        showUnitFilter: ui.showUnitFilter && units > 1,
        showBrokerRanking: ui.showBrokerRanking && users > 0,
        showTeamRanking: ui.showTeamRanking && teams > 1,
        showUnitSection: ui.showUnitSection && units > 0,
      );
    case 'team':
      return ui.copyWith(
        showUserFilter: ui.showUserFilter && users > 1,
        showTeamFilter: ui.showTeamFilter && teams > 1,
        showUnitFilter: false,
        showBrokerRanking: ui.showBrokerRanking && users > 0,
        showTeamRanking: ui.showTeamRanking && teams > 1,
        showUnitSection: false,
      );
    default:
      return ui.copyWith(
        showUserFilter: false,
        showTeamFilter: false,
        showUnitFilter: false,
        showBrokerRanking: false,
        showTeamRanking: false,
        showUnitSection: false,
      );
  }
}

/// `pruneFiltersToScope`: tira ids que o papel não pode filtrar.
SaleFormsOverviewFilters pruneOverviewFiltersToScope(
  SaleFormsOverviewFilters f, {
  required List<SaleFormsOverviewPickOption> users,
  required List<SaleFormsOverviewPickOption> teams,
  required List<SaleFormsOverviewPickOption> units,
  required SaleFormsOverviewScopeUi scope,
}) {
  final u = users.map((e) => e.id).toSet();
  final t = teams.map((e) => e.id).toSet();
  final un = units.map((e) => e.id).toSet();
  return f.copyWith(
    userIds: scope.showUserFilter
        ? f.userIds.where(u.contains).toList()
        : const [],
    teamIds: scope.showTeamFilter
        ? f.teamIds.where(t.contains).toList()
        : const [],
    unitIds: scope.showUnitFilter
        ? f.unitIds.where(un.contains).toList()
        : const [],
  );
}

// ─── Filtros guardados (D-4) ──────────────────────────────────────────────

/// Chave do web (`localStorage`) — no app ganha empresa e usuário para não
/// vazar filtros entre contas no mesmo aparelho.
const String kSaleFormsOverviewStorageKey = 'dashboard:sale-forms:overview:v1';

String saleFormsOverviewStorageKey({String? companyId, String? userId}) {
  final c = (companyId ?? '').trim();
  final u = (userId ?? '').trim();
  if (c.isEmpty && u.isEmpty) return kSaleFormsOverviewStorageKey;
  return '$kSaleFormsOverviewStorageKey:$c:$u';
}

String encodeOverviewFilters(SaleFormsOverviewFilters f) =>
    jsonEncode(f.toJson());

List<String> _strList(Object? v) => v is List
    ? v
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList()
    : const [];

/// `readStoredFilters` do web: vazio/ilegível = mês corrente; campos
/// ausentes caem no padrão; granularidade é recoerida ao intervalo.
SaleFormsOverviewFilters decodeOverviewFilters(String? raw, DateTime now) {
  final base = overviewCurrentMonthDefault(now);
  if (raw == null || raw.isEmpty) return base;
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return base;
    String? ymd(Object? v) =>
        v is String && overviewFromYmd(v) != null ? v : null;
    const grans = {'day', 'week', 'month', 'quarter', 'year'};
    final gran = m['granularity'];
    final status = _strList(
      m['status'],
    ).where((s) => kOverviewStatusOptions.any((o) => o.value == s)).toList();
    return coherentOverviewFilters(
      SaleFormsOverviewFilters(
        granularity: gran is String && grans.contains(gran)
            ? gran
            : base.granularity,
        dateFrom: ymd(m['dateFrom']) ?? base.dateFrom,
        dateTo: ymd(m['dateTo']) ?? base.dateTo,
        userIds: _strList(m['userIds']),
        teamIds: _strList(m['teamIds']),
        unitIds: _strList(m['unitIds']),
        status: status,
      ),
    );
  } catch (_) {
    return base;
  }
}

class SaleFormsOverviewFiltersStore {
  SaleFormsOverviewFiltersStore._();
  static final SaleFormsOverviewFiltersStore instance =
      SaleFormsOverviewFiltersStore._();

  Future<String> _key() async {
    String? companyId = ModuleAccessService.instance.selectedCompany?.id;
    try {
      companyId ??= await SecureStorageService.instance.getCompanyId();
    } catch (_) {}
    return saleFormsOverviewStorageKey(
      companyId: companyId,
      userId: ModuleAccessService.instance.userId,
    );
  }

  Future<SaleFormsOverviewFilters> read({DateTime? now}) async {
    final n = now ?? DateTime.now();
    try {
      final p = await SharedPreferences.getInstance();
      return decodeOverviewFilters(p.getString(await _key()), n);
    } catch (e) {
      debugPrint('[SALE_FORMS_PAINEL] ler filtros: $e');
      return overviewCurrentMonthDefault(n);
    }
  }

  Future<void> save(SaleFormsOverviewFilters f) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(await _key(), encodeOverviewFilters(f));
    } catch (e) {
      debugPrint('[SALE_FORMS_PAINEL] salvar filtros: $e');
    }
  }
}

// ─── Drill-down (D-2) ─────────────────────────────────────────────────────

/// Dimensão clicada no painel (`FichasListDrawerFilters` parcial do web).
/// `null` = herda do painel.
class OverviewDrillDimension {
  final List<String>? userIds;
  final List<String>? teamIds;
  final List<String>? unitIds;
  final List<SaleFormStatus>? statuses;
  final bool? sharedOnly;
  final bool? listDeletedOnly;

  const OverviewDrillDimension({
    this.userIds,
    this.teamIds,
    this.unitIds,
    this.statuses,
    this.sharedOnly,
    this.listDeletedOnly,
  });
}

/// Drill por status: "canceled" no painel = excluídas no período; quem tem
/// `sale_form:view_all` lista as excluídas (`listDeletedOnly`), os demais
/// caem em `status=canceled` — igual ao `openStatusDrawer` do web.
OverviewDrillDimension overviewStatusDrill(
  SaleFormStatus status, {
  required bool canViewAll,
}) {
  if (status == SaleFormStatus.canceled) {
    return canViewAll
        ? const OverviewDrillDimension(listDeletedOnly: true)
        : const OverviewDrillDimension(statuses: [SaleFormStatus.canceled]);
  }
  return OverviewDrillDimension(statuses: [status]);
}

/// `buildDrawerFromPanelSnapshot` + `toApiFilters` do web: herda período,
/// corretores, equipes, unidades e status do último painel carregado e
/// sobrepõe a dimensão clicada. Lista ordenada por criação, 20 por página.
SaleFormFilters buildOverviewDrillFilters(
  SaleFormsOverviewFilters snapshot, [
  OverviewDrillDimension dimension = const OverviewDrillDimension(),
]) {
  var statuses = [for (final s in snapshot.status) ?overviewStatusFromKey(s)];
  if (dimension.statuses != null) {
    statuses = [...dimension.statuses!];
  } else if (dimension.listDeletedOnly == true) {
    statuses = const [];
  }
  return SaleFormFilters(
    dateFrom: overviewFromYmd(snapshot.dateFrom),
    dateTo: overviewFromYmd(snapshot.dateTo),
    userIds: dimension.userIds ?? snapshot.userIds,
    teamIds: dimension.teamIds ?? snapshot.teamIds,
    unitIds: dimension.unitIds ?? snapshot.unitIds,
    statuses: statuses,
    sharedOnly: dimension.sharedOnly == true ? true : null,
    listDeletedOnly: dimension.listDeletedOnly == true ? true : null,
    page: 1,
    limit: 20,
    sortBy: 'createdAt',
    sortOrder: 'DESC',
  );
}
