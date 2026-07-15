// Modelos do módulo de Metas — espelham `goal.entity.ts` / DTOs do backend
// (`imobx/src/goals`) e os tipos do web (`imobx-front/src/types/goal.ts`).

import 'package:intl/intl.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

bool _toBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1';
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Tipo da meta (1:1 com `GoalType` do backend).
enum GoalType {
  salesValue('sales_value'),
  salesCount('sales_count'),
  rentalValue('rental_value'),
  rentalCount('rental_count'),
  revenue('revenue'),
  leads('leads'),
  conversions('conversions'),
  conversionRate('conversion_rate'),
  unknown('unknown');

  const GoalType(this.apiValue);
  final String apiValue;

  static GoalType fromRaw(String? raw) {
    final v = (raw ?? '').toLowerCase();
    for (final t in GoalType.values) {
      if (t.apiValue == v) return t;
    }
    return GoalType.unknown;
  }

  String get label {
    switch (this) {
      case GoalType.salesValue:
        return 'Valor de Vendas';
      case GoalType.salesCount:
        return 'Número de Vendas';
      case GoalType.rentalValue:
        return 'Valor de Aluguéis';
      case GoalType.rentalCount:
        return 'Número de Aluguéis';
      case GoalType.revenue:
        return 'Receita (Comissões)';
      case GoalType.leads:
        return 'Número de Leads';
      case GoalType.conversions:
        return 'Conversões';
      case GoalType.conversionRate:
        return 'Taxa de Conversão';
      case GoalType.unknown:
        return 'Meta';
    }
  }

  /// Metas monetárias (valor de vendas/aluguéis/receita).
  bool get isCurrency =>
      this == GoalType.salesValue ||
      this == GoalType.rentalValue ||
      this == GoalType.revenue;

  bool get isPercent => this == GoalType.conversionRate;

  /// Tipos selecionáveis no formulário (sem o `unknown`).
  static List<GoalType> get selectable =>
      GoalType.values.where((t) => t != GoalType.unknown).toList();
}

/// Período da meta (1:1 com `GoalPeriod` do backend).
enum GoalPeriod {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  quarterly('quarterly'),
  yearly('yearly'),
  unknown('unknown');

  const GoalPeriod(this.apiValue);
  final String apiValue;

  static GoalPeriod fromRaw(String? raw) {
    final v = (raw ?? '').toLowerCase();
    for (final p in GoalPeriod.values) {
      if (p.apiValue == v) return p;
    }
    return GoalPeriod.unknown;
  }

  String get label {
    switch (this) {
      case GoalPeriod.daily:
        return 'Diária';
      case GoalPeriod.weekly:
        return 'Semanal';
      case GoalPeriod.monthly:
        return 'Mensal';
      case GoalPeriod.quarterly:
        return 'Trimestral';
      case GoalPeriod.yearly:
        return 'Anual';
      case GoalPeriod.unknown:
        return 'Período';
    }
  }

  static List<GoalPeriod> get selectable =>
      GoalPeriod.values.where((p) => p != GoalPeriod.unknown).toList();
}

/// Escopo da meta (1:1 com `GoalScope` do backend).
enum GoalScope {
  company('company'),
  team('team'),
  user('user'),
  unknown('unknown');

  const GoalScope(this.apiValue);
  final String apiValue;

  static GoalScope fromRaw(String? raw) {
    final v = (raw ?? '').toLowerCase();
    for (final s in GoalScope.values) {
      if (s.apiValue == v) return s;
    }
    return GoalScope.unknown;
  }

  String get label {
    switch (this) {
      case GoalScope.company:
        return 'Empresa';
      case GoalScope.team:
        return 'Equipe';
      case GoalScope.user:
        return 'Corretor Individual';
      case GoalScope.unknown:
        return 'Escopo';
    }
  }

  static List<GoalScope> get selectable =>
      GoalScope.values.where((s) => s != GoalScope.unknown).toList();
}

/// Status da meta (1:1 com `GoalStatus` do backend).
enum GoalStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled'),
  unknown('unknown');

  const GoalStatus(this.apiValue);
  final String apiValue;

  static GoalStatus fromRaw(String? raw) {
    final v = (raw ?? '').toLowerCase();
    if (v == 'canceled') return GoalStatus.cancelled;
    for (final s in GoalStatus.values) {
      if (s.apiValue == v) return s;
    }
    return GoalStatus.unknown;
  }

  String get label {
    switch (this) {
      case GoalStatus.draft:
        return 'Rascunho';
      case GoalStatus.active:
        return 'Ativa';
      case GoalStatus.completed:
        return 'Completada';
      case GoalStatus.failed:
        return 'Falhou';
      case GoalStatus.cancelled:
        return 'Cancelada';
      case GoalStatus.unknown:
        return 'Meta';
    }
  }

  static List<GoalStatus> get selectable =>
      GoalStatus.values.where((s) => s != GoalStatus.unknown).toList();
}

/// Cores sugeridas para metas (paridade com `GOAL_COLORS` do web).
const List<String> kGoalColors = [
  '#10B981', // Verde
  '#3B82F6', // Azul
  '#8B5CF6', // Roxo
  '#F59E0B', // Laranja
  '#EF4444', // Vermelho
  '#EC4899', // Rosa
  '#14B8A6', // Teal
  '#6366F1', // Indigo
];

/// Ícones (emoji) sugeridos (paridade com `GOAL_ICONS` do web).
const List<String> kGoalIcons = [
  '🎯', '🏆', '💰', '📈', '🚀', '⭐', '🔥', '💎', '📊', '🎖️',
];

final NumberFormat _moneyRounded = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 0,
);
final NumberFormat _compactMoney = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat _plain = NumberFormat.decimalPattern('pt_BR');
final NumberFormat _percent = NumberFormat('#,##0.#', 'pt_BR');

/// Formata um valor segundo o tipo da meta (moeda / % / contagem) —
/// mesma regra do `formatValue` do GoalCard web.
String formatGoalValue(double value, GoalType type) {
  if (type.isCurrency) return _moneyRounded.format(value);
  if (type.isPercent) return '${_percent.format(value)}%';
  return _plain.format(value.round());
}

/// Versão compacta (KPIs/hero) — `R$ 1,2 mi` para moeda.
String formatGoalValueCompact(double value, GoalType type) {
  if (type.isCurrency) return _compactMoney.format(value);
  return formatGoalValue(value, type);
}

/// Meta — espelha o `formatGoalResponse` do `goals.service.ts`.
class Goal {
  final String id;
  final String title;
  final String? description;
  final GoalType type;
  final GoalPeriod period;
  final GoalScope scope;
  final double targetValue;
  final double currentValue;
  final double progress; // 0..100
  final double remaining;
  final DateTime? startDate;
  final DateTime? endDate;
  final GoalStatus status;
  final bool isActive;
  final bool isCompanyWide;
  final String? color;
  final String? icon;
  final String? notes;
  final DateTime? achievedAt;

  // Tempo
  final int daysTotal;
  final int daysElapsed;
  final int daysRemaining;

  // Análise
  final bool isOnTrack;
  final double dailyTarget;
  final double projectedValue;

  // Vínculos (o backend devolve objetos `user`/`team` aninhados)
  final String? userId;
  final String? userName;
  final String? teamId;
  final String? teamName;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Goal({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    required this.period,
    required this.scope,
    required this.targetValue,
    required this.currentValue,
    required this.progress,
    required this.remaining,
    this.startDate,
    this.endDate,
    required this.status,
    required this.isActive,
    required this.isCompanyWide,
    this.color,
    this.icon,
    this.notes,
    this.achievedAt,
    required this.daysTotal,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.isOnTrack,
    required this.dailyTarget,
    required this.projectedValue,
    this.userId,
    this.userName,
    this.teamId,
    this.teamName,
    this.createdAt,
    this.updatedAt,
  });

  /// Progresso normalizado 0..1 (para barras/gauges).
  double get progressRatio => (progress / 100).clamp(0.0, 1.0);

  /// Nome do responsável exibível (corretor ou equipe), se houver.
  String? get ownerLabel {
    if (scope == GoalScope.user && (userName ?? '').trim().isNotEmpty) {
      return userName!.trim();
    }
    if (scope == GoalScope.team && (teamName ?? '').trim().isNotEmpty) {
      return teamName!.trim();
    }
    return null;
  }

  factory Goal.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final user = nested('user');
    final team = nested('team');

    return Goal(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      type: GoalType.fromRaw(json['type']?.toString()),
      period: GoalPeriod.fromRaw(json['period']?.toString()),
      scope: GoalScope.fromRaw(json['scope']?.toString()),
      targetValue: _toDouble(json['targetValue'] ?? json['target_value']),
      currentValue: _toDouble(json['currentValue'] ?? json['current_value']),
      progress: _toDouble(json['progress']),
      remaining: _toDouble(json['remaining']),
      startDate: _toDate(json['startDate'] ?? json['start_date']),
      endDate: _toDate(json['endDate'] ?? json['end_date']),
      status: GoalStatus.fromRaw(json['status']?.toString()),
      isActive: _toBool(json['isActive'] ?? json['is_active']),
      isCompanyWide: _toBool(json['isCompanyWide'] ?? json['is_company_wide']),
      color: json['color']?.toString(),
      icon: json['icon']?.toString(),
      notes: json['notes']?.toString(),
      achievedAt: _toDate(json['achievedAt'] ?? json['achieved_at']),
      daysTotal: _toInt(json['daysTotal'] ?? json['days_total']),
      daysElapsed: _toInt(json['daysElapsed'] ?? json['days_elapsed']),
      daysRemaining: _toInt(json['daysRemaining'] ?? json['days_remaining']),
      isOnTrack: _toBool(json['isOnTrack'] ?? json['is_on_track']),
      dailyTarget: _toDouble(json['dailyTarget'] ?? json['daily_target']),
      projectedValue:
          _toDouble(json['projectedValue'] ?? json['projected_value']),
      userId: user?['id']?.toString() ?? json['userId']?.toString(),
      userName: user?['name']?.toString(),
      teamId: team?['id']?.toString() ?? json['teamId']?.toString(),
      teamName: team?['name']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Resposta de `GET /goals` — `{ goals, total, active, completed, failed }`.
class GoalsListResult {
  final List<Goal> goals;
  final int total;
  final int active;
  final int completed;
  final int failed;

  const GoalsListResult({
    required this.goals,
    required this.total,
    required this.active,
    required this.completed,
    required this.failed,
  });

  static const empty = GoalsListResult(
    goals: [],
    total: 0,
    active: 0,
    completed: 0,
    failed: 0,
  );

  factory GoalsListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['goals'] ?? json['data'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Goal.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Goal>[];
    return GoalsListResult(
      goals: list,
      total: _toInt(json['total'] ?? list.length),
      active: _toInt(json['active']),
      completed: _toInt(json['completed']),
      failed: _toInt(json['failed']),
    );
  }
}

/// Ponto do histórico de evolução (`GET /goals/:id/analytics`).
class GoalHistoryPoint {
  final DateTime? date;
  final double value; // valor DIÁRIO (não acumulado)
  final double progress; // % acumulado no dia

  const GoalHistoryPoint({
    required this.date,
    required this.value,
    required this.progress,
  });

  factory GoalHistoryPoint.fromJson(Map<String, dynamic> json) {
    return GoalHistoryPoint(
      date: _toDate(json['date']),
      value: _toDouble(json['value']),
      progress: _toDouble(json['progress']),
    );
  }
}

/// Melhor/pior dia da análise.
class GoalDayStat {
  final DateTime? date;
  final double value;

  const GoalDayStat({required this.date, required this.value});

  factory GoalDayStat.fromJson(Map<String, dynamic> json) {
    return GoalDayStat(date: _toDate(json['date']), value: _toDouble(json['value']));
  }
}

/// Análise detalhada — resposta de `GET /goals/:id/analytics`.
class GoalAnalytics {
  final String goalId;
  final String title;
  final double currentProgress;
  final DateTime? projectedCompletion;
  final double averageDailyProgress;
  final GoalDayStat? bestDay;
  final GoalDayStat? worstDay;
  final List<GoalHistoryPoint> history;
  final List<String> insights;

  const GoalAnalytics({
    required this.goalId,
    required this.title,
    required this.currentProgress,
    this.projectedCompletion,
    required this.averageDailyProgress,
    this.bestDay,
    this.worstDay,
    required this.history,
    required this.insights,
  });

  factory GoalAnalytics.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final rawHistory = json['history'];
    final rawInsights = json['insights'];
    final best = nested('bestDay');
    final worst = nested('worstDay');

    return GoalAnalytics(
      goalId: json['goalId']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      currentProgress: _toDouble(json['currentProgress'] ?? json['progress']),
      projectedCompletion: _toDate(json['projectedCompletion']),
      averageDailyProgress: _toDouble(json['averageDailyProgress']),
      bestDay: best == null ? null : GoalDayStat.fromJson(best),
      worstDay: worst == null ? null : GoalDayStat.fromJson(worst),
      history: rawHistory is List
          ? rawHistory
              .whereType<Map>()
              .map((e) =>
                  GoalHistoryPoint.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      insights: rawInsights is List
          ? rawInsights.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Filtros de `GET /goals` (espelha `FilterGoalsDto` + `GoalFilters` do web).
class GoalFilters {
  final GoalType? type;
  final GoalPeriod? period;
  final GoalScope? scope;
  final GoalStatus? status;
  final String? userId;
  final String? teamId;
  final bool? onlyActive;
  final String? search;

  const GoalFilters({
    this.type,
    this.period,
    this.scope,
    this.status,
    this.userId,
    this.teamId,
    this.onlyActive,
    this.search,
  });

  static const none = GoalFilters();

  /// Quantidade de filtros "do modal" ativos (busca e status da aba não contam).
  int get activeCount {
    var count = 0;
    if (type != null) count++;
    if (period != null) count++;
    if (scope != null) count++;
    if (userId != null && userId!.isNotEmpty) count++;
    if (teamId != null && teamId!.isNotEmpty) count++;
    if (onlyActive == true) count++;
    return count;
  }

  GoalFilters copyWith({
    GoalType? type,
    GoalPeriod? period,
    GoalScope? scope,
    GoalStatus? status,
    String? userId,
    String? teamId,
    bool? onlyActive,
    String? search,
  }) {
    return GoalFilters(
      type: type ?? this.type,
      period: period ?? this.period,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      teamId: teamId ?? this.teamId,
      onlyActive: onlyActive ?? this.onlyActive,
      search: search ?? this.search,
    );
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{};
    if (type != null) out['type'] = type!.apiValue;
    if (period != null) out['period'] = period!.apiValue;
    if (scope != null) out['scope'] = scope!.apiValue;
    if (status != null) out['status'] = status!.apiValue;
    if (userId != null && userId!.isNotEmpty) out['userId'] = userId!;
    if (teamId != null && teamId!.isNotEmpty) out['teamId'] = teamId!;
    if (onlyActive != null) out['onlyActive'] = onlyActive! ? 'true' : 'false';
    final s = search?.trim();
    if (s != null && s.isNotEmpty) out['search'] = s;
    return out;
  }
}

/// Opção simples (id + nome) para selects de corretor/equipe.
class GoalOption {
  final String id;
  final String name;

  const GoalOption({required this.id, required this.name});

  factory GoalOption.fromJson(Map<String, dynamic> json) {
    return GoalOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

/// Opções para os formulários/filtros — corretores e equipes da empresa.
class GoalFormOptions {
  final List<GoalOption> users;
  final List<GoalOption> teams;

  const GoalFormOptions({required this.users, required this.teams});

  static const empty = GoalFormOptions(users: [], teams: []);
}
