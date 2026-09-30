import 'package:intl/intl.dart';

import 'sdr_metrics_model.dart';

/// Presets de período do dashboard SDR (equivalente mobile dos filtros de
/// data do `SDRDashboardFiltersDrawer` web).
enum SdrPeriodPreset {
  today('Hoje'),
  last7('7 dias'),
  last30('30 dias'),
  last90('90 dias'),
  thisMonth('Este mês'),
  custom('Personalizado');

  const SdrPeriodPreset(this.label);

  final String label;
}

/// Modo das listas de leads no `GET /kanban/analytics/sdr/metrics`.
///
/// 29/09/2026 (sdr-02): o back devolve as cinco listas de leads
/// (transferList, lostLeadsList, qualificationLeadsList, periodLeadsList,
/// dailyProductivity) quando `lists` vem ausente — ~4,5 MB na União. Em rede
/// móvel, com o timeout de 30 s do ApiService, isso virava "sem conexão". O
/// web abre com `none` e só pede `full` quando um drill-down abre; o app
/// passou a fazer o mesmo.
enum SdrListsMode {
  none('none'),
  full('full');

  const SdrListsMode(this.apiValue);
  final String apiValue;
}

/// Catálogo necessário para traduzir os filtros no recorte que vai à API —
/// equipes visíveis (GET /kanban/teams?allActive=true) e funis ativos não
/// pessoais dessas equipes (GET /kanban/projects/teams).
class SdrQueryContext {
  const SdrQueryContext({
    this.teams = const [],
    this.projects = const [],
    this.openColumnId,
  });

  final List<SdrTeamOption> teams;
  final List<SdrProjectOption> projects;

  /// Coluna "Aberto" da produtividade diária (opcional, como no web).
  final String? openColumnId;

  static const SdrQueryContext empty = SdrQueryContext();
}

/// Mesma heurística do `sdrDefaultTeamFilter.ts` do web: o schema não tem
/// flag `isSdr` na equipe, então o nome decide ("SDR", "Pré-Atendimento").
final RegExp _kSdrNameRegex =
    RegExp(r'\bsdr\b|pr[eé][-\s]?aten', caseSensitive: false);

bool isSdrTeamName(String? name) =>
    name != null && name.isNotEmpty && _kSdrNameRegex.hasMatch(name);

/// `defaultSdrTeamFilterIds` do web: equipes SDR por nome; sem nenhuma, a
/// única equipe do usuário ou todas.
List<String>? defaultSdrTeamFilterIds(List<SdrTeamOption> teams) {
  if (teams.isEmpty) return null;
  final sdrOnly = teams.where((t) => isSdrTeamName(t.name)).toList();
  if (sdrOnly.isNotEmpty) return sdrOnly.map((t) => t.id).toList();
  return teams.map((t) => t.id).toList();
}

/// Filtros aplicados ao `GET /kanban/analytics/sdr/metrics` e às consultas
/// irmãs (daily-productivity, brokers-stagnation, subtask-activity).
/// Datas viajam como `yyyy-MM-dd` (paridade `buildSdrQueryParamsFromFilters`).
///
/// 29/09/2026 (sdr-03): além de período e equipe, o web filtra por funis,
/// campanhas (Meta + Sistema), mídias/origens, pessoas e tags do card. O app
/// passou a ter os mesmos sete recortes.
class SdrDashboardFilters {
  const SdrDashboardFilters({
    this.preset = SdrPeriodPreset.last30,
    this.customStart,
    this.customEnd,
    this.teamIds = const <String>{},
    this.projectIds = const <String>{},
    this.campaignIds = const <String>{},
    this.sources = const <String>{},
    this.agentIds = const <String>{},
    this.tagIds = const <String>{},
  });

  final SdrPeriodPreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Set<String> teamIds;
  final Set<String> projectIds;
  final Set<String> campaignIds;
  final Set<String> sources;
  final Set<String> agentIds;
  final Set<String> tagIds;

  static const SdrDashboardFilters initial = SdrDashboardFilters();

  /// Intervalo efetivo (datas locais, sem hora).
  ({DateTime start, DateTime end}) resolvedRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case SdrPeriodPreset.today:
        return (start: today, end: today);
      case SdrPeriodPreset.last7:
        return (start: today.subtract(const Duration(days: 6)), end: today);
      case SdrPeriodPreset.last30:
        return (start: today.subtract(const Duration(days: 29)), end: today);
      case SdrPeriodPreset.last90:
        return (start: today.subtract(const Duration(days: 89)), end: today);
      case SdrPeriodPreset.thisMonth:
        return (start: DateTime(now.year, now.month, 1), end: today);
      case SdrPeriodPreset.custom:
        final s = customStart ?? today.subtract(const Duration(days: 29));
        final e = customEnd ?? today;
        return e.isBefore(s) ? (start: e, end: s) : (start: s, end: e);
    }
  }

  /// Rótulo humano do período (ex.: `01/06 — 30/06`).
  String periodLabel() {
    if (preset != SdrPeriodPreset.custom) return preset.label;
    final r = resolvedRange();
    final fmt = DateFormat('dd/MM/yy', 'pt_BR');
    return '${fmt.format(r.start)} — ${fmt.format(r.end)}';
  }

  /// Quantos filtros “não padrão” estão ativos (badge do botão de filtros).
  int get activeCount {
    var n = 0;
    if (preset != SdrPeriodPreset.last30) n++;
    if (teamIds.isNotEmpty) n++;
    if (projectIds.isNotEmpty) n++;
    if (campaignIds.isNotEmpty) n++;
    if (sources.isNotEmpty) n++;
    if (agentIds.isNotEmpty) n++;
    if (tagIds.isNotEmpty) n++;
    return n;
  }

  /// Recorte enviado à API, espelho de `buildSdrQueryParamsFromFilters`
  /// (imobx-front/src/utils/sdrExportFilters.ts).
  ///
  /// 29/09/2026 (sdr-09): com equipe escolhida, o web NÃO manda o teamId
  /// estreito — `column.team` pode divergir da equipe operacional (bug
  /// Base/Esmeraldas) e o total zerava. Ele converte a equipe nos funis dela
  /// (`projectId`) e manda `teamId` = equipes SDR padrão. O app mandava o
  /// teamId cru e mostrava outro número para a mesma equipe.
  ///
  /// Valores viajam repetidos (`campaignId=a&campaignId=b`), nunca em CSV:
  /// campanha do Sistema é identificada pelo NOME, que pode ter vírgula.
  Map<String, List<String>> toQuery(
    SdrQueryContext ctx, {
    SdrListsMode? lists = SdrListsMode.none,
    bool includeOpenColumn = true,
  }) {
    final out = <String, List<String>>{};
    void put(String key, Iterable<String> values) {
      final clean = values
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
      if (clean.isNotEmpty) out[key] = clean;
    }

    if (lists != null) out['lists'] = [lists.apiValue];

    final r = resolvedRange();
    final ymd = DateFormat('yyyy-MM-dd');
    out['startDate'] = [ymd.format(r.start)];
    out['endDate'] = [ymd.format(r.end)];

    // Funil explícito delimita por projectId (igual ao CRM) — sem teamId.
    final allowedProjects = ctx.projects.map((p) => p.id).toSet();
    final explicitProjects =
        projectIds.where((id) => allowedProjects.contains(id)).toList();
    if (explicitProjects.isNotEmpty) {
      put('projectId', explicitProjects);
    } else if (teamIds.isNotEmpty) {
      final teamProjects = ctx.projects
          .where((p) => p.belongsToAny(teamIds))
          .map((p) => p.id)
          .toList();
      if (teamProjects.isNotEmpty) {
        put('projectId', teamProjects);
        final defaults = defaultSdrTeamFilterIds(ctx.teams);
        put('teamId',
            (defaults != null && defaults.isNotEmpty) ? defaults : teamIds);
      } else {
        put('teamId', teamIds);
      }
    }
    // Sem funil e sem equipe: não restringe (o back conta todos os funis),
    // exatamente como o default do web.

    put('campaignId', campaignIds);
    put('agentId', agentIds);
    put('source', sources);
    put('tagId', tagIds);
    final open = ctx.openColumnId?.trim() ?? '';
    if (includeOpenColumn && open.isNotEmpty) out['openColumnId'] = [open];
    return out;
  }

  SdrDashboardFilters copyWith({
    SdrPeriodPreset? preset,
    DateTime? customStart,
    DateTime? customEnd,
    Set<String>? teamIds,
    Set<String>? projectIds,
    Set<String>? campaignIds,
    Set<String>? sources,
    Set<String>? agentIds,
    Set<String>? tagIds,
  }) {
    return SdrDashboardFilters(
      preset: preset ?? this.preset,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      teamIds: teamIds ?? this.teamIds,
      projectIds: projectIds ?? this.projectIds,
      campaignIds: campaignIds ?? this.campaignIds,
      sources: sources ?? this.sources,
      agentIds: agentIds ?? this.agentIds,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}

/// Monta a query string com chaves repetidas (o `ApiService.get` só aceita
/// `Map<String, String>`, que não repete chave).
String encodeSdrQuery(Map<String, List<String>> params) {
  final parts = <String>[];
  params.forEach((key, values) {
    for (final v in values) {
      parts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(v)}');
    }
  });
  return parts.join('&');
}
