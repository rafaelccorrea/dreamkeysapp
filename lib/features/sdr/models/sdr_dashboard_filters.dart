import 'package:intl/intl.dart';

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

/// Filtros aplicados ao `GET /kanban/analytics/sdr/metrics`.
/// Datas viajam como `yyyy-MM-dd` (paridade `buildSdrQueryParamsFromFilters`).
class SdrDashboardFilters {
  const SdrDashboardFilters({
    this.preset = SdrPeriodPreset.last30,
    this.customStart,
    this.customEnd,
    this.teamIds = const <String>{},
  });

  final SdrPeriodPreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Set<String> teamIds;

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
    return n;
  }

  /// Query string parameters. `teamId` vai separado por vírgula — o backend
  /// aceita repetido OU csv (`parseSdrQueryList`).
  Map<String, String> toQueryParams() {
    final r = resolvedRange();
    final ymd = DateFormat('yyyy-MM-dd');
    final params = <String, String>{
      'startDate': ymd.format(r.start),
      'endDate': ymd.format(r.end),
      // O dashboard mobile não usa a lista de transferências — zera para
      // aliviar o payload (os agregados continuam completos).
      'transferListLimit': '0',
    };
    if (teamIds.isNotEmpty) {
      params['teamId'] = teamIds.join(',');
    }
    return params;
  }

  SdrDashboardFilters copyWith({
    SdrPeriodPreset? preset,
    DateTime? customStart,
    DateTime? customEnd,
    Set<String>? teamIds,
  }) {
    return SdrDashboardFilters(
      preset: preset ?? this.preset,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      teamIds: teamIds ?? this.teamIds,
    );
  }
}
