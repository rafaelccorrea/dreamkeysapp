// Modelos do módulo de Automações — espelham `types/automation.ts` do
// imobx-front e as entidades `automation*.entity.ts` do backend (NestJS).
//
// Endpoints consumidos (AutomationsController, módulo `automations`):
//   GET    /automations                     → lista (array cru de Automation)
//   GET    /automations/templates           → templates disponíveis
//   POST   /automations/templates/:id       → cria a partir do template
//   GET    /automations/:id                 → detalhe
//   PATCH  /automations/:id/toggle          → { isActive }
//   PATCH  /automations/:id/config          → { config }
//   GET    /automations/:id/statistics      → estatísticas agregadas
//   GET    /automations/:id/executions      → { executions, pagination }
//   GET    /automations/:id/executions/:eid → execução + logs

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

List<int> _toIntList(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .toList();
  }
  if (v is num) return [v.toInt()];
  return const [];
}

// ─── Categoria (1:1 com `Category` do web) ───────────────────────────────────

enum AutomationCategory {
  process,
  financial,
  rental,
  crm,
  marketing,
  unknown;

  static AutomationCategory fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'process':
        return AutomationCategory.process;
      case 'financial':
        return AutomationCategory.financial;
      case 'rental':
        return AutomationCategory.rental;
      case 'crm':
        return AutomationCategory.crm;
      case 'marketing':
        return AutomationCategory.marketing;
      default:
        return AutomationCategory.unknown;
    }
  }

  /// Rótulos EXATOS do web (`getCategoryLabel` da AutomationsPage.tsx).
  String get label {
    switch (this) {
      case AutomationCategory.process:
        return 'Processo';
      case AutomationCategory.financial:
        return 'Financeiro';
      case AutomationCategory.rental:
        return 'Locação';
      case AutomationCategory.crm:
        return 'Funil de Vendas';
      case AutomationCategory.marketing:
        return 'Marketing';
      case AutomationCategory.unknown:
        return 'Outros';
    }
  }
}

// ─── Status de execução ──────────────────────────────────────────────────────

enum AutomationExecutionStatus {
  success,
  error,
  partial,
  unknown;

  static AutomationExecutionStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'success':
        return AutomationExecutionStatus.success;
      case 'error':
        return AutomationExecutionStatus.error;
      case 'partial':
        return AutomationExecutionStatus.partial;
      default:
        return AutomationExecutionStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case AutomationExecutionStatus.success:
        return 'Sucesso';
      case AutomationExecutionStatus.error:
        return 'Erro';
      case AutomationExecutionStatus.partial:
        return 'Parcial';
      case AutomationExecutionStatus.unknown:
        return 'Execução';
    }
  }

  /// Valor enviado na query `status` do endpoint de execuções.
  String get apiValue => name;
}

// ─── Nível de log ────────────────────────────────────────────────────────────

enum AutomationLogLevel {
  debug,
  info,
  warn,
  error,
  unknown;

  static AutomationLogLevel fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'debug':
        return AutomationLogLevel.debug;
      case 'info':
        return AutomationLogLevel.info;
      case 'warn':
      case 'warning':
        return AutomationLogLevel.warn;
      case 'error':
        return AutomationLogLevel.error;
      default:
        return AutomationLogLevel.unknown;
    }
  }

  String get label {
    switch (this) {
      case AutomationLogLevel.debug:
        return 'DEBUG';
      case AutomationLogLevel.info:
        return 'INFO';
      case AutomationLogLevel.warn:
        return 'AVISO';
      case AutomationLogLevel.error:
        return 'ERRO';
      case AutomationLogLevel.unknown:
        return 'LOG';
    }
  }
}

// ─── Configuração ────────────────────────────────────────────────────────────

/// Chaves de destinatário conhecidas (ordem de exibição = ordem do web).
const List<String> kAutomationRecipientKeys = [
  'corretor',
  'cliente',
  'proprietario',
  'admin',
  'manager',
  'lead',
];

/// Rótulos dos destinatários (EXATOS do web — `formatRecipientLabel`).
String automationRecipientLabel(String key) {
  switch (key) {
    case 'corretor':
      return 'Corretor';
    case 'cliente':
      return 'Cliente';
    case 'proprietario':
      return 'Proprietário';
    case 'admin':
      return 'Gerenciador';
    case 'manager':
      return 'Gerente';
    case 'lead':
      return 'Lead';
    default:
      return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
  }
}

/// Canais editáveis no app (paridade com o web, que só expõe email + inApp).
const List<String> kAutomationChannelKeys = ['email', 'inApp'];

String automationChannelLabel(String key) {
  switch (key) {
    case 'email':
      return 'Email';
    case 'inApp':
      return 'In-App';
    case 'whatsapp':
      return 'WhatsApp';
    case 'sms':
      return 'SMS';
    default:
      return key;
  }
}

/// Configuração da automação (`AutomationConfig` do web). Os campos que o app
/// não edita (conditions, customUsers, createOn*, etc.) são preservados em
/// [extras] e reenviados intactos no PATCH — round-trip sem perda.
class AutomationConfig {
  final bool? enabled;
  final Map<String, bool> recipients;
  final List<int> timingDays;
  final List<int> timingHours;
  final bool immediate;
  final Map<String, bool> channels;
  final String customMessage;

  /// Campos desconhecidos do topo do config (preservados no PATCH).
  final Map<String, dynamic> extras;

  /// Campos desconhecidos dentro de `timing` (além de days/hours/immediate).
  final Map<String, dynamic> timingExtras;

  /// Campos desconhecidos dentro de `recipients` (ex.: customUsers).
  final Map<String, dynamic> recipientsExtras;

  /// Canais que o app não edita (whatsapp/sms) preservados como vieram.
  final Map<String, dynamic> channelsExtras;

  const AutomationConfig({
    this.enabled,
    this.recipients = const {},
    this.timingDays = const [],
    this.timingHours = const [],
    this.immediate = false,
    this.channels = const {},
    this.customMessage = '',
    this.extras = const {},
    this.timingExtras = const {},
    this.recipientsExtras = const {},
    this.channelsExtras = const {},
  });

  factory AutomationConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AutomationConfig();

    final extras = <String, dynamic>{};
    final timingExtras = <String, dynamic>{};
    final recipientsExtras = <String, dynamic>{};
    final channelsExtras = <String, dynamic>{};

    final recipients = <String, bool>{};
    final rawRecipients = json['recipients'];
    if (rawRecipients is Map) {
      rawRecipients.forEach((key, value) {
        final k = key.toString();
        if (kAutomationRecipientKeys.contains(k)) {
          recipients[k] = _toBool(value);
        } else {
          recipientsExtras[k] = value;
        }
      });
    }

    final channels = <String, bool>{};
    final rawChannels = json['channels'];
    if (rawChannels is Map) {
      rawChannels.forEach((key, value) {
        final k = key.toString();
        if (kAutomationChannelKeys.contains(k)) {
          channels[k] = _toBool(value);
        } else {
          channelsExtras[k] = value;
        }
      });
    }

    var timingDays = const <int>[];
    var timingHours = const <int>[];
    var immediate = false;
    final rawTiming = json['timing'];
    if (rawTiming is Map) {
      rawTiming.forEach((key, value) {
        switch (key.toString()) {
          case 'days':
            timingDays = _toIntList(value);
            break;
          case 'hours':
            timingHours = _toIntList(value);
            break;
          case 'immediate':
            immediate = _toBool(value);
            break;
          default:
            timingExtras[key.toString()] = value;
        }
      });
    }

    json.forEach((key, value) {
      const known = {
        'enabled',
        'recipients',
        'timing',
        'channels',
        'customMessage',
      };
      if (!known.contains(key)) extras[key] = value;
    });

    return AutomationConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
      recipients: recipients,
      timingDays: timingDays,
      timingHours: timingHours,
      immediate: immediate,
      channels: channels,
      customMessage: json['customMessage']?.toString() ?? '',
      extras: extras,
      timingExtras: timingExtras,
      recipientsExtras: recipientsExtras,
      channelsExtras: channelsExtras,
    );
  }

  AutomationConfig copyWith({
    bool? enabled,
    Map<String, bool>? recipients,
    List<int>? timingDays,
    List<int>? timingHours,
    bool? immediate,
    Map<String, bool>? channels,
    String? customMessage,
  }) {
    return AutomationConfig(
      enabled: enabled ?? this.enabled,
      recipients: recipients ?? this.recipients,
      timingDays: timingDays ?? this.timingDays,
      timingHours: timingHours ?? this.timingHours,
      immediate: immediate ?? this.immediate,
      channels: channels ?? this.channels,
      customMessage: customMessage ?? this.customMessage,
      extras: extras,
      timingExtras: timingExtras,
      recipientsExtras: recipientsExtras,
      channelsExtras: channelsExtras,
    );
  }

  /// Payload de `PATCH /automations/:id/config` — mantém os campos que o app
  /// não conhece exatamente como vieram do backend.
  Map<String, dynamic> toJson() {
    final timing = <String, dynamic>{
      ...timingExtras,
      if (timingDays.isNotEmpty) 'days': timingDays,
      if (timingHours.isNotEmpty) 'hours': timingHours,
      'immediate': immediate,
    };
    return <String, dynamic>{
      ...extras,
      if (enabled != null) 'enabled': enabled,
      'recipients': {...recipientsExtras, ...recipients},
      'timing': timing,
      'channels': {...channelsExtras, ...channels},
      'customMessage': customMessage,
    };
  }

  /// Há alguma janela de disparo configurável? (para telas decidirem o que
  /// exibir em templates de evento imediato, como o checklist automático).
  bool get hasTiming =>
      timingDays.isNotEmpty || timingHours.isNotEmpty || immediate;
}

// ─── Automação ───────────────────────────────────────────────────────────────

/// Rótulo pt-BR do tipo da automação (EXATO do web — `formatTypeLabel`).
String automationTypeLabel(String? type) {
  const map = <String, String>{
    'checklist_automatic': 'Checklist Automático',
    'checklist_reminder': 'Lembrete de Checklist',
    'payment_reminder': 'Lembrete de Pagamento',
    'payment_overdue': 'Pagamento Atrasado',
    'contract_expiring': 'Contrato Expirando',
    'contract_expired': 'Contrato Expirado',
    'client_followup': 'Follow-up de Cliente',
    'mcmv_lead_followup': 'Follow-up de Lead MCMV',
    'lead_followup': 'Follow-up de Leads',
    'match_notification': 'Notificação de Match',
    'subscription_expiring': 'Assinatura Expirando',
    'subscription_expired': 'Assinatura Expirada',
    'inspection_reminder': 'Lembrete de Vistoria',
    'appointment_reminder': 'Lembrete de Agendamento',
    'expense_reminder': 'Lembrete de Despesa',
    'expense_overdue': 'Despesa Vencida',
  };
  if (type == null || type.isEmpty) return 'Tipo não informado';
  return map[type] ?? type;
}

class Automation {
  final String id;
  final String name;
  final String description;
  final String type;
  final AutomationCategory category;
  final String icon;
  final bool isActive;
  final AutomationConfig config;
  final int executionCount;
  final int successfulExecutions;
  final int failedExecutions;
  final DateTime? lastExecutionAt;

  /// 'active' | 'inactive' | 'error' (entidade do backend).
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Automation({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.category,
    required this.icon,
    required this.isActive,
    required this.config,
    required this.executionCount,
    required this.successfulExecutions,
    required this.failedExecutions,
    this.lastExecutionAt,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasFailures => failedExecutions > 0 || status == 'error';

  String get typeLabel => automationTypeLabel(type);

  factory Automation.fromJson(Map<String, dynamic> json) {
    return Automation(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      category: AutomationCategory.fromRaw(json['category']?.toString()),
      icon: json['icon']?.toString() ?? '',
      isActive: _toBool(json['isActive'] ?? json['is_active']),
      config: AutomationConfig.fromJson(
        json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : null,
      ),
      executionCount: _toInt(json['executionCount'] ?? json['execution_count']),
      successfulExecutions: _toInt(
          json['successfulExecutions'] ?? json['successful_executions']),
      failedExecutions:
          _toInt(json['failedExecutions'] ?? json['failed_executions']),
      lastExecutionAt:
          _toDate(json['lastExecutionAt'] ?? json['last_execution_at']),
      status: json['status']?.toString() ?? 'inactive',
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Automation copyWith({bool? isActive, String? status}) {
    return Automation(
      id: id,
      name: name,
      description: description,
      type: type,
      category: category,
      icon: icon,
      isActive: isActive ?? this.isActive,
      config: config,
      executionCount: executionCount,
      successfulExecutions: successfulExecutions,
      failedExecutions: failedExecutions,
      lastExecutionAt: lastExecutionAt,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

// ─── Template ────────────────────────────────────────────────────────────────

class AutomationTemplate {
  final String id;
  final String name;
  final String description;
  final String type;
  final AutomationCategory category;
  final String icon;
  final AutomationConfig defaultConfig;

  const AutomationTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.category,
    required this.icon,
    required this.defaultConfig,
  });

  String get typeLabel => automationTypeLabel(type);

  factory AutomationTemplate.fromJson(Map<String, dynamic> json) {
    return AutomationTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      category: AutomationCategory.fromRaw(json['category']?.toString()),
      icon: json['icon']?.toString() ?? '',
      defaultConfig: AutomationConfig.fromJson(
        json['defaultConfig'] is Map
            ? Map<String, dynamic>.from(json['defaultConfig'] as Map)
            : null,
      ),
    );
  }
}

// ─── Execução & logs ─────────────────────────────────────────────────────────

class AutomationLog {
  final String id;
  final AutomationLogLevel level;
  final String type;
  final String message;
  final String? details;
  final DateTime? createdAt;

  const AutomationLog({
    required this.id,
    required this.level,
    required this.type,
    required this.message,
    this.details,
    this.createdAt,
  });

  factory AutomationLog.fromJson(Map<String, dynamic> json) {
    return AutomationLog(
      id: json['id']?.toString() ?? '',
      level: AutomationLogLevel.fromRaw(json['level']?.toString()),
      type: json['type']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      details: json['details']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
    );
  }
}

class AutomationExecution {
  final String id;
  final String automationId;
  final AutomationExecutionStatus status;
  final int notificationsSent;
  final int itemsProcessed;
  final int errorsCount;
  final int executionTimeMs;
  final String? errorMessage;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final List<AutomationLog> logs;

  const AutomationExecution({
    required this.id,
    required this.automationId,
    required this.status,
    required this.notificationsSent,
    required this.itemsProcessed,
    required this.errorsCount,
    required this.executionTimeMs,
    this.errorMessage,
    this.metadata = const {},
    this.createdAt,
    this.logs = const [],
  });

  factory AutomationExecution.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['logs'];
    return AutomationExecution(
      id: json['id']?.toString() ?? '',
      automationId:
          (json['automationId'] ?? json['automation_id'])?.toString() ?? '',
      status: AutomationExecutionStatus.fromRaw(json['status']?.toString()),
      notificationsSent:
          _toInt(json['notificationsSent'] ?? json['notifications_sent']),
      itemsProcessed: _toInt(json['itemsProcessed'] ?? json['items_processed']),
      errorsCount: _toInt(json['errorsCount'] ?? json['errors_count']),
      executionTimeMs:
          _toInt(json['executionTimeMs'] ?? json['execution_time_ms']),
      errorMessage:
          (json['errorMessage'] ?? json['error_message'])?.toString(),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      logs: rawLogs is List
          ? rawLogs
              .whereType<Map>()
              .map((e) =>
                  AutomationLog.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Resposta paginada de `GET /automations/:id/executions`.
class ExecutionPageResult {
  final List<AutomationExecution> executions;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const ExecutionPageResult({
    required this.executions,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  static const empty = ExecutionPageResult(
    executions: [],
    page: 1,
    limit: 20,
    total: 0,
    totalPages: 1,
  );

  bool get hasMore => page < totalPages;

  factory ExecutionPageResult.fromJson(Map<String, dynamic> json) {
    final raw = json['executions'] ?? json['data'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) =>
                AutomationExecution.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <AutomationExecution>[];
    final pagination = json['pagination'] is Map
        ? Map<String, dynamic>.from(json['pagination'] as Map)
        : json;
    return ExecutionPageResult(
      executions: list,
      page: _toInt(pagination['page'], 1),
      limit: _toInt(pagination['limit'], 20),
      total: _toInt(pagination['total'], list.length),
      totalPages: _toInt(pagination['totalPages'], 1),
    );
  }
}

/// Filtros de `GET /automations/:id/executions`.
class ExecutionFilters {
  final AutomationExecutionStatus? status;
  final DateTime? from;
  final DateTime? to;
  final int page;
  final int limit;

  const ExecutionFilters({
    this.status,
    this.from,
    this.to,
    this.page = 1,
    this.limit = 20,
  });

  ExecutionFilters copyWith({
    AutomationExecutionStatus? status,
    bool clearStatus = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? page,
    int? limit,
  }) {
    return ExecutionFilters(
      status: clearStatus ? null : (status ?? this.status),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  int get activeCount =>
      (status != null ? 1 : 0) + (from != null ? 1 : 0) + (to != null ? 1 : 0);

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (status != null && status != AutomationExecutionStatus.unknown) {
      out['status'] = status!.apiValue;
    }
    if (from != null) out['from'] = from!.toIso8601String();
    if (to != null) out['to'] = to!.toIso8601String();
    return out;
  }
}

// ─── Estatísticas ────────────────────────────────────────────────────────────

/// Resposta de `GET /automations/:id/statistics`.
class AutomationStatistics {
  final int totalExecutions;
  final int successfulExecutions;
  final int failedExecutions;
  final DateTime? lastExecution;
  final double averageExecutionTime;

  const AutomationStatistics({
    required this.totalExecutions,
    required this.successfulExecutions,
    required this.failedExecutions,
    this.lastExecution,
    required this.averageExecutionTime,
  });

  static const zero = AutomationStatistics(
    totalExecutions: 0,
    successfulExecutions: 0,
    failedExecutions: 0,
    averageExecutionTime: 0,
  );

  double get successRate => totalExecutions == 0
      ? 0
      : (successfulExecutions / totalExecutions) * 100;

  factory AutomationStatistics.fromJson(Map<String, dynamic> json) {
    return AutomationStatistics(
      totalExecutions: _toInt(json['totalExecutions']),
      successfulExecutions: _toInt(json['successfulExecutions']),
      failedExecutions: _toInt(json['failedExecutions']),
      lastExecution: _toDate(json['lastExecution']),
      averageExecutionTime: _toDouble(json['averageExecutionTime']),
    );
  }
}
