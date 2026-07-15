/// Modelos do domínio **Assinaturas & Planos** — paridade com
/// `imobx-front/src/types/subscriptionTypes.ts` e com os DTOs do Nest
/// (`subscriptions.controller.ts`, `subscription-usage.dto.ts`,
/// `subscription-filters.dto.ts`). Todos os `fromJson` são defensivos:
/// números podem chegar como string ("299.99"), módulos como `String` ou
/// `{ code }`, e respostas podem vir embrulhadas em `{ data: ... }`.
library;

// ─── Helpers defensivos ───────────────────────────────────────────────────────

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed != null) return parsed;
  }
  return fallback;
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Módulos podem vir como `['kanban_management']` ou `[{code: '...'}]`.
List<String> asModuleCodes(dynamic v) {
  if (v is! List) return const [];
  return v
      .map((m) {
        if (m is String) return m;
        final map = asMap(m);
        return map?['code']?.toString() ?? '';
      })
      .where((c) => c.isNotEmpty)
      .toList();
}

// ─── Status ───────────────────────────────────────────────────────────────────

/// Rótulos pt-BR dos status de assinatura (mesmos valores do enum do backend).
String subscriptionStatusLabel(String status) {
  switch (status.toLowerCase().trim()) {
    case 'active':
      return 'Ativa';
    case 'suspended':
      return 'Suspensa';
    case 'cancelled':
      return 'Cancelada';
    case 'expired':
      return 'Expirada';
    case 'pending':
      return 'Pendente';
    case 'inactive':
      return 'Inativa';
    case 'managed_exempt':
      return 'Conta gerenciada';
    case 'custom_plan':
      return 'Plano personalizado';
    default:
      return status.isEmpty ? '—' : status;
  }
}

/// Rótulos pt-BR dos módulos (paridade com
/// `imobx-front/src/utils/subscriptionModuleDisplay.tsx`).
const Map<String, String> kModuleLabels = {
  'user_management': 'Gestão de Usuários',
  'basic_reports': 'Relatórios Básicos',
  'advanced_reports': 'Relatórios Avançados',
  'team_management': 'Gestão de Equipes',
  'property_management': 'Gestão de Propriedades',
  'client_management': 'Gestão de Clientes',
  'kanban_management': 'Gestão Kanban',
  'financial_management': 'Gestão Financeira',
  'calendar_management': 'Gestão de Calendário',
  'rental_management': 'Gestão de Locações',
  'commission_management': 'Gestão de Comissões',
  'notes': 'Anotações',
  'match_system': 'Sistema de Matches',
  'sale_forms': 'Fichas de Venda',
};

String moduleLabel(String code) {
  final known = kModuleLabels[code];
  if (known != null) return known;
  // Fallback legível: "some_module_code" → "Some Module Code".
  return code
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ─── Métrica de uso ───────────────────────────────────────────────────────────

/// Um recurso medido (empresas, usuários, imóveis, storage, API, tokens IA).
/// `limit <= 0` (ou -1) significa **ilimitado**.
class UsageMetric {
  final double used;
  final double limit;
  final double percentage;
  final bool isOverLimit;

  const UsageMetric({
    required this.used,
    required this.limit,
    required this.percentage,
    required this.isOverLimit,
  });

  bool get isUnlimited => limit <= 0;
  bool get isNearLimit => !isUnlimited && percentage >= 80;

  factory UsageMetric.fromJson(Map<String, dynamic> json) {
    // `apiCalls` usa `usedThisMonth`; os demais usam `used`.
    final used = asDouble(json['used'] ?? json['usedThisMonth']);
    final limit = asDouble(json['limit'], -1);
    var pct = asDouble(json['percentage']);
    if (pct == 0 && limit > 0 && used > 0) pct = (used / limit) * 100;
    return UsageMetric(
      used: used,
      limit: limit,
      percentage: pct,
      isOverLimit: asBool(json['isOverLimit']) || (limit > 0 && used > limit),
    );
  }

  static UsageMetric? tryParse(dynamic v) {
    final map = asMap(v);
    return map == null ? null : UsageMetric.fromJson(map);
  }
}

/// Detalhamento de cobrança por usuário (assentos inclusos + adicionais).
class SeatBilling {
  final int includedUsers;
  final int currentUsers;
  final int additionalUsers;
  final double pricePerAdditionalUser;
  final double additionalCost;

  const SeatBilling({
    required this.includedUsers,
    required this.currentUsers,
    required this.additionalUsers,
    required this.pricePerAdditionalUser,
    required this.additionalCost,
  });

  static SeatBilling? tryParse(dynamic v) {
    final map = asMap(v);
    if (map == null) return null;
    return SeatBilling(
      includedUsers: asInt(map['includedUsers']),
      currentUsers: asInt(map['currentUsers']),
      additionalUsers: asInt(map['additionalUsers']),
      pricePerAdditionalUser: asDouble(map['pricePerAdditionalUser']),
      additionalCost: asDouble(map['additionalCost']),
    );
  }
}

// ─── Uso da assinatura (GET /subscriptions/my-usage) ─────────────────────────

class SubscriptionUsage {
  final String subscriptionId;
  final String planName;
  final String planType;
  final double monthlyPrice;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final int daysRemaining;
  final bool isTrialActive;
  final DateTime? trialEndsAt;
  final int? trialDaysRemaining;
  final UsageMetric? companies;
  final UsageMetric? users;
  final UsageMetric? properties;
  final UsageMetric? storage;
  final UsageMetric? apiCalls;
  final UsageMetric? aiTokens;
  final List<String> activeModules;
  final List<String> alerts;
  final SeatBilling? seats;

  const SubscriptionUsage({
    required this.subscriptionId,
    required this.planName,
    required this.planType,
    required this.monthlyPrice,
    required this.status,
    this.startDate,
    this.endDate,
    required this.daysRemaining,
    required this.isTrialActive,
    this.trialEndsAt,
    this.trialDaysRemaining,
    this.companies,
    this.users,
    this.properties,
    this.storage,
    this.apiCalls,
    this.aiTokens,
    required this.activeModules,
    required this.alerts,
    this.seats,
  });

  bool get isCustomPlan =>
      planType.toLowerCase() == 'custom' ||
      planName.toLowerCase().contains('custom');

  /// Uso "com significado" — paridade com `hasMeaningfulSubscriptionUsage`
  /// do web (payloads vazios de onboarding não contam).
  bool get isMeaningful =>
      subscriptionId.trim().isNotEmpty || planName.trim().isNotEmpty;

  factory SubscriptionUsage.fromJson(Map<String, dynamic> json) {
    return SubscriptionUsage(
      subscriptionId: json['subscriptionId']?.toString() ?? '',
      planName: json['planName']?.toString() ?? '',
      planType: json['planType']?.toString() ?? '',
      monthlyPrice: asDouble(json['monthlyPrice']),
      status: json['status']?.toString() ?? '',
      startDate: asDate(json['startDate']),
      endDate: asDate(json['endDate']),
      daysRemaining: asInt(json['daysRemaining']),
      isTrialActive: asBool(json['isTrialActive']),
      trialEndsAt: asDate(json['trialEndsAt']),
      trialDaysRemaining: json['trialDaysRemaining'] == null
          ? null
          : asInt(json['trialDaysRemaining']),
      companies: UsageMetric.tryParse(json['companies']),
      users: UsageMetric.tryParse(json['users']),
      properties: UsageMetric.tryParse(json['properties']),
      storage: UsageMetric.tryParse(json['storage']),
      apiCalls: UsageMetric.tryParse(json['apiCalls']),
      aiTokens: UsageMetric.tryParse(json['aiTokens']),
      activeModules: json['activeModules'] is List
          ? (json['activeModules'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      alerts: json['alerts'] is List
          ? (json['alerts'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      seats: SeatBilling.tryParse(json['seats']),
    );
  }
}

// ─── Assinatura ativa (GET /subscriptions/my-active-subscription) ────────────

/// Resumo normalizado da assinatura ativa. A API tem três formatos:
/// nova estrutura `{type: 'subscription', subscription: {...}}`,
/// `{type: 'custom_plan', ...}` e o DTO legado plano. `fromResponse`
/// devolve `null` quando não há assinatura (`{message: ...}`).
class ActiveSubscription {
  final String id;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final double price;
  final String planId;
  final String planName;
  final String planType;
  final String planDescription;
  final List<String> modules;
  final DateTime? nextBillingDate;
  final DateTime? trialEndsAt;
  final int currentCompanies;
  final int? maxCompanies;
  final String? notes;
  final bool hasAccess;
  final String? reason;
  final bool isCustomPlan;
  final int? daysUntilExpiry;
  final bool isExpired;

  const ActiveSubscription({
    required this.id,
    required this.status,
    this.startDate,
    this.endDate,
    required this.price,
    required this.planId,
    required this.planName,
    required this.planType,
    required this.planDescription,
    required this.modules,
    this.nextBillingDate,
    this.trialEndsAt,
    required this.currentCompanies,
    this.maxCompanies,
    this.notes,
    required this.hasAccess,
    this.reason,
    required this.isCustomPlan,
    this.daysUntilExpiry,
    required this.isExpired,
  });

  static ActiveSubscription? fromResponse(Map<String, dynamic> json) {
    final type = json['type']?.toString();

    // Sem assinatura: `{ message: "Nenhuma assinatura..." }`.
    if (type == null &&
        json['message'] != null &&
        json['subscription'] == null &&
        json['id'] == null) {
      return null;
    }

    if (type == 'subscription') {
      final sub = asMap(json['subscription']) ?? const {};
      final plan = asMap(sub['plan']) ?? const {};
      final limits = asMap(sub['limits']) ?? const {};
      final companies = asMap(limits['companies']) ?? const {};
      final validations = asMap(sub['validations']) ?? const {};
      return ActiveSubscription(
        id: sub['id']?.toString() ?? '',
        status: sub['status']?.toString() ?? 'inactive',
        startDate: asDate(sub['startDate']),
        endDate: asDate(sub['endDate']),
        price: asDouble(sub['price'] ?? plan['price']),
        planId: plan['id']?.toString() ?? sub['planId']?.toString() ?? '',
        planName: plan['name']?.toString() ?? 'Plano',
        planType: plan['type']?.toString() ?? '',
        planDescription: plan['description']?.toString() ?? '',
        modules: asModuleCodes(plan['modules']),
        nextBillingDate: asDate(sub['nextBillingDate']),
        trialEndsAt: asDate(sub['trialEndsAt']),
        currentCompanies: asInt(companies['current']),
        maxCompanies:
            companies['max'] == null ? null : asInt(companies['max']),
        notes: asStringOrNull(sub['notes']),
        hasAccess: asBool(json['hasAccess'], true),
        reason: asStringOrNull(json['reason']),
        isCustomPlan: (plan['type']?.toString() ?? '') == 'custom',
        daysUntilExpiry: validations['daysUntilExpiry'] == null
            ? null
            : asInt(validations['daysUntilExpiry']),
        isExpired: asBool(validations['isExpired']),
      );
    }

    if (type == 'custom_plan') {
      final limits = asMap(json['limits']) ?? const {};
      final companies = asMap(limits['companies']) ?? const {};
      return ActiveSubscription(
        id: 'custom-plan',
        status: 'active',
        price: 0,
        planId: 'custom_plan',
        planName: 'Plano Personalizado',
        planType: 'custom',
        planDescription: '',
        modules: const [],
        currentCompanies: asInt(companies['current']),
        maxCompanies:
            companies['max'] == null ? null : asInt(companies['max']),
        hasAccess: asBool(json['hasAccess'], true),
        isCustomPlan: true,
        isExpired: false,
      );
    }

    // Formato legado (SubscriptionResponseDto): `plan` é string ou objeto.
    final planRaw = json['plan'];
    final planMap = asMap(planRaw);
    return ActiveSubscription(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'inactive',
      startDate: asDate(json['startDate']),
      endDate: asDate(json['endDate']),
      price: asDouble(json['price'] ?? planMap?['price']),
      planId: json['planId']?.toString() ?? planMap?['id']?.toString() ?? '',
      planName: planMap?['name']?.toString() ??
          (planRaw is String && planRaw.isNotEmpty ? planRaw : 'Plano'),
      planType: planMap?['type']?.toString() ?? '',
      planDescription: planMap?['description']?.toString() ?? '',
      modules: asModuleCodes(planMap?['modules']),
      nextBillingDate: asDate(json['nextBillingDate']),
      trialEndsAt: asDate(json['trialEndsAt']),
      currentCompanies: asInt(json['currentCompanies']),
      maxCompanies: null,
      notes: asStringOrNull(json['notes']),
      hasAccess: true,
      isCustomPlan: (planMap?['type']?.toString() ?? '') == 'custom',
      isExpired: false,
    );
  }
}

// ─── Planos (vitrine) ─────────────────────────────────────────────────────────

/// Limites de um plano da vitrine (`/plans/pricing-page`). `-1` = ilimitado.
class PricingLimits {
  final int companies;
  final int users;
  final int properties;
  final int storage;

  const PricingLimits({
    this.companies = 0,
    this.users = 0,
    this.properties = 0,
    this.storage = 0,
  });

  factory PricingLimits.fromJson(Map<String, dynamic> json) {
    return PricingLimits(
      companies: asInt(json['companies']),
      users: asInt(json['users']),
      properties: asInt(json['properties']),
      storage: asInt(json['storage']),
    );
  }
}

class PricingModule {
  final String code;
  final String name;

  const PricingModule({required this.code, required this.name});

  factory PricingModule.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    return PricingModule(
      code: code,
      name: json['name']?.toString() ?? moduleLabel(code),
    );
  }
}

/// Um plano da vitrine — normaliza tanto `/plans/pricing-page`
/// (basic/professional/custom) quanto `GET /plans` (fallback).
class PricingPlan {
  final String key; // 'basic' | 'professional' | 'custom'
  final String name;
  final String description;
  final double price;

  /// `true` quando o preço é "a partir de" (plano custom com basePrice).
  final bool isBasePrice;
  final bool popular;
  final List<PricingModule> modules;
  final PricingLimits limits;
  final List<String> features;
  final int? trialDays;

  const PricingPlan({
    required this.key,
    required this.name,
    required this.description,
    required this.price,
    this.isBasePrice = false,
    this.popular = false,
    required this.modules,
    required this.limits,
    required this.features,
    this.trialDays,
  });

  factory PricingPlan.fromPricingJson(
    String key,
    Map<String, dynamic> json,
  ) {
    final isCustom = key == 'custom';
    final limitsMap = asMap(json[isCustom ? 'includedLimits' : 'limits']);
    return PricingPlan(
      key: key,
      name: json['name']?.toString() ?? 'Plano',
      description: json['description']?.toString() ?? '',
      price: asDouble(json[isCustom ? 'basePrice' : 'price']),
      isBasePrice: isCustom,
      popular: asBool(json['popular'], key == 'professional'),
      modules: json['modules'] is List
          ? (json['modules'] as List)
              .map(asMap)
              .whereType<Map<String, dynamic>>()
              .map(PricingModule.fromJson)
              .toList()
          : const [],
      limits: limitsMap != null
          ? PricingLimits.fromJson(limitsMap)
          : const PricingLimits(),
      features: json['features'] is List
          ? (json['features'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      trialDays:
          json['trialDays'] == null ? null : asInt(json['trialDays']),
    );
  }

  /// Fallback a partir de `GET /plans` (entidade Plan do backend).
  factory PricingPlan.fromPlanJson(Map<String, dynamic> json) {
    final features = asMap(json['features']) ?? const {};
    final type = json['type']?.toString() ?? 'custom';
    return PricingPlan(
      key: type,
      name: json['name']?.toString() ?? 'Plano',
      description: json['description']?.toString() ?? '',
      price: asDouble(json['price']),
      isBasePrice: type == 'custom',
      popular: type == 'professional' || type == 'pro',
      modules: asModuleCodes(json['modules'])
          .map((c) => PricingModule(code: c, name: moduleLabel(c)))
          .toList(),
      limits: PricingLimits(
        companies: asInt(json['maxCompanies'] ?? features['maxCompanies'], 1),
        users: asInt(features['maxUsers'] ?? json['maxUsers']),
        properties:
            asInt(features['maxProperties'] ?? json['maxProperties']),
        storage: asInt(features['storageGB'] ?? json['maxStorage']),
      ),
      features: const [],
      trialDays:
          json['trialDays'] == null ? null : asInt(json['trialDays']),
    );
  }
}

// ─── Gestão master (GET /subscriptions/admin/all-subscriptions) ──────────────

class AdminSubscriptionItem {
  final String id;
  final String status;
  final double price;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? nextBillingDate;
  final DateTime? trialEndsAt;
  final DateTime? createdAt;
  final String? notes;
  final String userName;
  final String userEmail;
  final String planId;
  final String planName;
  final String planType;
  final SubscriptionUsage? usage;

  const AdminSubscriptionItem({
    required this.id,
    required this.status,
    required this.price,
    this.startDate,
    this.endDate,
    this.nextBillingDate,
    this.trialEndsAt,
    this.createdAt,
    this.notes,
    required this.userName,
    required this.userEmail,
    required this.planId,
    required this.planName,
    required this.planType,
    this.usage,
  });

  factory AdminSubscriptionItem.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']) ?? const {};
    final plan = asMap(json['plan']) ?? const {};
    final usageMap = asMap(json['usage']);
    return AdminSubscriptionItem(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'inactive',
      price: asDouble(json['price'] ?? plan['price']),
      startDate: asDate(json['startDate']),
      endDate: asDate(json['endDate']),
      nextBillingDate: asDate(json['nextBillingDate']),
      trialEndsAt: asDate(json['trialEndsAt']),
      createdAt: asDate(json['createdAt']),
      notes: asStringOrNull(json['notes']),
      userName: user['name']?.toString() ?? '—',
      userEmail: user['email']?.toString() ?? '',
      planId: plan['id']?.toString() ?? json['planId']?.toString() ?? '',
      planName: plan['name']?.toString() ?? 'Plano',
      planType: plan['type']?.toString() ?? '',
      usage: usageMap != null ? SubscriptionUsage.fromJson(usageMap) : null,
    );
  }
}

class AdminSubscriptionsSummary {
  final int totalSubscriptions;
  final int activeSubscriptions;
  final int expiredSubscriptions;
  final int cancelledSubscriptions;
  final double totalRevenue;
  final int totalUsers;
  final int totalCompanies;

  const AdminSubscriptionsSummary({
    this.totalSubscriptions = 0,
    this.activeSubscriptions = 0,
    this.expiredSubscriptions = 0,
    this.cancelledSubscriptions = 0,
    this.totalRevenue = 0,
    this.totalUsers = 0,
    this.totalCompanies = 0,
  });

  static const zero = AdminSubscriptionsSummary();

  factory AdminSubscriptionsSummary.fromJson(Map<String, dynamic> json) {
    return AdminSubscriptionsSummary(
      totalSubscriptions: asInt(json['totalSubscriptions']),
      activeSubscriptions: asInt(json['activeSubscriptions']),
      expiredSubscriptions: asInt(json['expiredSubscriptions']),
      cancelledSubscriptions: asInt(json['cancelledSubscriptions']),
      totalRevenue: asDouble(json['totalRevenue']),
      totalUsers: asInt(json['totalUsers']),
      totalCompanies: asInt(json['totalCompanies']),
    );
  }
}

class AdminSubscriptionsResult {
  final List<AdminSubscriptionItem> items;
  final int total;
  final int page;
  final int totalPages;
  final AdminSubscriptionsSummary summary;

  const AdminSubscriptionsResult({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.summary,
  });

  static const empty = AdminSubscriptionsResult(
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
    summary: AdminSubscriptionsSummary.zero,
  );

  factory AdminSubscriptionsResult.fromJson(Map<String, dynamic> json) {
    final list = json['subscriptions'];
    final summaryMap = asMap(json['summary']);
    return AdminSubscriptionsResult(
      items: list is List
          ? list
              .map(asMap)
              .whereType<Map<String, dynamic>>()
              .map(AdminSubscriptionItem.fromJson)
              .toList()
          : const [],
      total: asInt(json['total']),
      page: asInt(json['page'], 1),
      totalPages: asInt(json['totalPages'], 1),
      summary: summaryMap != null
          ? AdminSubscriptionsSummary.fromJson(summaryMap)
          : AdminSubscriptionsSummary.zero,
    );
  }
}

/// Filtros da gestão — espelha `SubscriptionFiltersDto` do backend.
class AdminSubscriptionFilters {
  final String? companyName;
  final String? companyCnpj;
  final String? userName;
  final String? userEmail;
  final String? status;
  final String? planType; // 'basic' | 'professional' | 'custom'
  final int page;
  final int limit;

  const AdminSubscriptionFilters({
    this.companyName,
    this.companyCnpj,
    this.userName,
    this.userEmail,
    this.status,
    this.planType,
    this.page = 1,
    this.limit = 20,
  });

  /// Filtros “de gaveta” ativos (status é controlado pelas abas, não conta).
  int get activeCount => [
        companyName,
        companyCnpj,
        userName,
        userEmail,
        planType,
      ].where((v) => v != null && v.trim().isNotEmpty).length;

  AdminSubscriptionFilters copyWith({
    String? companyName,
    String? companyCnpj,
    String? userName,
    String? userEmail,
    String? status,
    String? planType,
    int? page,
    int? limit,
    bool clearStatus = false,
  }) {
    return AdminSubscriptionFilters(
      companyName: companyName ?? this.companyName,
      companyCnpj: companyCnpj ?? this.companyCnpj,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      status: clearStatus ? null : (status ?? this.status),
      planType: planType ?? this.planType,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  Map<String, String> toQueryParams() {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) params[key] = v;
    }

    put('companyName', companyName);
    put('companyCnpj', companyCnpj);
    put('userName', userName);
    put('userEmail', userEmail);
    put('status', status);
    put('planType', planType);
    return params;
  }
}
