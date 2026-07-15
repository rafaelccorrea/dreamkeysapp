// Modelos do módulo MCMV (Minha Casa Minha Vida) — espelham 1:1 os tipos do
// imobx-front (`src/types/mcmv.ts`) e os DTOs do backend
// (`imobx/src/dto/mcmv/*` + controllers `mcmv*.controller.ts`).

// ─── Parse helpers defensivos ────────────────────────────────────────────────

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
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase().trim();
  return s == 'true' || s == '1' || s == 'yes' || s == 'sim';
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? _toOptString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

// ─── Permissões / módulo (strings exatas do web + backend) ──────────────────

/// Permissões do MCMV, 1:1 com `Permission` enum do backend e o gating do
/// `Drawer.tsx` / `misc.routes.tsx` do imobx-front. Mantidas aqui (privadas à
/// feature) até a fiação central movê-las para `AppPermissions`.
class McmvPermissions {
  McmvPermissions._();

  static const String view = 'mcmv:view';
  static const String leadView = 'mcmv:lead:view';
  static const String leadCapture = 'mcmv:lead:capture';
  static const String leadUpdate = 'mcmv:lead:update';
  static const String leadAssign = 'mcmv:lead:assign';
  static const String leadRate = 'mcmv:lead:rate';
  static const String leadConvert = 'mcmv:lead:convert';
  static const String blacklistView = 'mcmv:blacklist:view';
  static const String blacklistManage = 'mcmv:blacklist:manage';
  static const String templateView = 'mcmv:template:view';
  static const String templateManage = 'mcmv:template:manage';

  /// O módulo pode aparecer em `availableModules` como `mcmv` (ModuleType do
  /// backend) OU `mcmv_management` (alias usado em algumas camadas — ver
  /// `imobx-front/src/utils/moduleMapping.ts`, MODULE_ALIASES). Cheque os dois.
  static const List<String> moduleAliases = ['mcmv', 'mcmv_management'];
}

/// Rotas da feature (usadas em `Navigator.pushNamed`). A fiação central
/// registra os mesmos valores em `AppRoutes`.
class McmvRoutes {
  McmvRoutes._();

  static const String leads = '/mcmv/leads';
  static const String blacklist = '/mcmv/blacklist';
  static const String templates = '/mcmv/templates';
  static String leadDetails(String id) => '/mcmv/leads/$id';
}

// ─── Leads ───────────────────────────────────────────────────────────────────

/// Status do lead (1:1 com `LeadStatus` do web: new/contacted/qualified/
/// converted/lost).
enum McmvLeadStatus {
  newLead,
  contacted,
  qualified,
  converted,
  lost,
  unknown;

  static McmvLeadStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'new':
        return McmvLeadStatus.newLead;
      case 'contacted':
        return McmvLeadStatus.contacted;
      case 'qualified':
        return McmvLeadStatus.qualified;
      case 'converted':
        return McmvLeadStatus.converted;
      case 'lost':
        return McmvLeadStatus.lost;
      default:
        return McmvLeadStatus.unknown;
    }
  }

  /// Valor enviado à API (`PUT /mcmv/leads/:id/status`).
  String get apiValue {
    switch (this) {
      case McmvLeadStatus.newLead:
        return 'new';
      case McmvLeadStatus.contacted:
        return 'contacted';
      case McmvLeadStatus.qualified:
        return 'qualified';
      case McmvLeadStatus.converted:
        return 'converted';
      case McmvLeadStatus.lost:
        return 'lost';
      case McmvLeadStatus.unknown:
        return 'new';
    }
  }

  String get label {
    switch (this) {
      case McmvLeadStatus.newLead:
        return 'Novo';
      case McmvLeadStatus.contacted:
        return 'Contactado';
      case McmvLeadStatus.qualified:
        return 'Qualificado';
      case McmvLeadStatus.converted:
        return 'Convertido';
      case McmvLeadStatus.lost:
        return 'Perdido';
      case McmvLeadStatus.unknown:
        return 'Lead';
    }
  }

  /// Lead "vivo": ainda dá para trabalhar (nem convertido, nem perdido).
  bool get isOpen =>
      this != McmvLeadStatus.converted && this != McmvLeadStatus.lost;
}

/// Faixa de renda do programa (faixa1/faixa2/faixa3).
enum McmvIncomeRange {
  faixa1,
  faixa2,
  faixa3,
  unknown;

  static McmvIncomeRange fromRaw(String? raw) {
    final s = (raw ?? '').toLowerCase().replaceAll(' ', '').trim();
    switch (s) {
      case 'faixa1':
      case 'faixa_1':
      case '1':
        return McmvIncomeRange.faixa1;
      case 'faixa2':
      case 'faixa_2':
      case '2':
        return McmvIncomeRange.faixa2;
      case 'faixa3':
      case 'faixa_3':
      case '3':
        return McmvIncomeRange.faixa3;
      default:
        return McmvIncomeRange.unknown;
    }
  }

  String get label {
    switch (this) {
      case McmvIncomeRange.faixa1:
        return 'Faixa 1';
      case McmvIncomeRange.faixa2:
        return 'Faixa 2';
      case McmvIncomeRange.faixa3:
        return 'Faixa 3';
      case McmvIncomeRange.unknown:
        return 'Sem faixa';
    }
  }
}

/// Lead MCMV — espelha `MCMVLead` do web.
class McmvLead {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String cpf;
  final double monthlyIncome;
  final int familySize;
  final String incomeRangeRaw;
  final McmvIncomeRange incomeRange;
  final bool eligible;
  final String city;
  final String state;
  final McmvLeadStatus status;
  final int score;
  final String? clientId;
  final String? companyId;
  final String? assignedToUserId;
  final DateTime? lastContactAt;
  final int followUpCount;
  final int? rating;
  final String? ratingComment;
  final DateTime? ratedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const McmvLead({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.cpf,
    required this.monthlyIncome,
    required this.familySize,
    required this.incomeRangeRaw,
    required this.incomeRange,
    required this.eligible,
    required this.city,
    required this.state,
    required this.status,
    required this.score,
    this.clientId,
    this.companyId,
    this.assignedToUserId,
    this.lastContactAt,
    required this.followUpCount,
    this.rating,
    this.ratingComment,
    this.ratedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Já foi capturado por uma empresa (o backend só devolve leads livres ou
  /// da própria empresa — então "capturado" aqui significa "é nosso").
  bool get isCaptured => (companyId ?? '').isNotEmpty;

  /// Já virou cliente do sistema.
  bool get isConverted => (clientId ?? '').isNotEmpty;

  /// Rótulo "Cidade, UF" (tolerante a campos vazios).
  String get locationLabel {
    final c = city.trim();
    final s = state.trim().toUpperCase();
    if (c.isEmpty && s.isEmpty) return '';
    if (c.isEmpty) return s;
    if (s.isEmpty) return c;
    return '$c, $s';
  }

  factory McmvLead.fromJson(Map<String, dynamic> json) {
    final rawRange =
        (json['incomeRange'] ?? json['income_range'])?.toString() ?? '';
    return McmvLead(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      cpf: json['cpf']?.toString() ?? '',
      monthlyIncome: _toDouble(json['monthlyIncome'] ?? json['monthly_income']),
      familySize: _toInt(json['familySize'] ?? json['family_size']),
      incomeRangeRaw: rawRange,
      incomeRange: McmvIncomeRange.fromRaw(rawRange),
      eligible: _toBool(json['eligible']),
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      status: McmvLeadStatus.fromRaw(json['status']?.toString()),
      score: _toInt(json['score']),
      clientId: _toOptString(json['clientId'] ?? json['client_id']),
      companyId: _toOptString(json['companyId'] ?? json['company_id']),
      assignedToUserId: _toOptString(
          json['assignedToUserId'] ?? json['assigned_to_user_id']),
      lastContactAt: _toDate(json['lastContactAt'] ?? json['last_contact_at']),
      followUpCount: _toInt(json['followUpCount'] ?? json['follow_up_count']),
      rating: json['rating'] == null ? null : _toInt(json['rating']),
      ratingComment:
          _toOptString(json['ratingComment'] ?? json['rating_comment']),
      ratedAt: _toDate(json['ratedAt'] ?? json['rated_at']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Resposta paginada de `GET /mcmv/leads` (PaginatedResponseDto do backend).
class McmvLeadListResult {
  final List<McmvLead> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const McmvLeadListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  static const empty = McmvLeadListResult(
    items: [],
    total: 0,
    page: 1,
    limit: 20,
    totalPages: 0,
    hasNext: false,
    hasPrev: false,
  );

  factory McmvLeadListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] ?? json['data'] ?? json['leads'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => McmvLead.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <McmvLead>[];
    return McmvLeadListResult(
      items: list,
      total: json['total'] == null ? list.length : _toInt(json['total']),
      page: json['page'] == null ? 1 : _toInt(json['page']),
      limit: json['limit'] == null ? list.length : _toInt(json['limit']),
      totalPages: json['totalPages'] == null ? 1 : _toInt(json['totalPages']),
      hasNext: _toBool(json['hasNext']),
      hasPrev: _toBool(json['hasPrev']),
    );
  }
}

/// Filtros de `GET /mcmv/leads` — mesmos query params do `mcmvApi.listLeads`
/// do web (status, city, state, eligible, minScore, page, limit).
class McmvLeadFilters {
  final McmvLeadStatus? status;
  final String? city;
  final String? state;
  final bool? eligible;
  final int? minScore;
  final int page;
  final int limit;

  const McmvLeadFilters({
    this.status,
    this.city,
    this.state,
    this.eligible,
    this.minScore,
    this.page = 1,
    this.limit = 20,
  });

  /// Quantidade de filtros "avançados" ativos (para o badge do botão de
  /// filtros — status/faixa ficam nos chips da página, fora desta conta).
  int get advancedCount {
    var n = 0;
    if ((city ?? '').trim().isNotEmpty) n++;
    if ((state ?? '').trim().isNotEmpty) n++;
    if (eligible != null) n++;
    if (minScore != null && minScore! > 0) n++;
    return n;
  }

  McmvLeadFilters copyWith({
    McmvLeadStatus? status,
    bool clearStatus = false,
    String? city,
    String? state,
    bool? eligible,
    bool clearEligible = false,
    int? minScore,
    int? page,
    int? limit,
  }) {
    return McmvLeadFilters(
      status: clearStatus ? null : (status ?? this.status),
      city: city ?? this.city,
      state: state ?? this.state,
      eligible: clearEligible ? null : (eligible ?? this.eligible),
      minScore: minScore ?? this.minScore,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (status != null && status != McmvLeadStatus.unknown) {
      out['status'] = status!.apiValue;
    }
    final c = city?.trim();
    if (c != null && c.isNotEmpty) out['city'] = c;
    final s = state?.trim();
    if (s != null && s.isNotEmpty) out['state'] = s;
    if (eligible != null) out['eligible'] = eligible! ? 'true' : 'false';
    if (minScore != null && minScore! > 0) out['minScore'] = '${minScore!}';
    return out;
  }
}

/// Resposta de `POST /mcmv/leads/:id/convert`.
class McmvConvertResult {
  final String clientId;
  final McmvLead? lead;

  const McmvConvertResult({required this.clientId, this.lead});

  factory McmvConvertResult.fromJson(Map<String, dynamic> json) {
    final rawLead = json['lead'];
    return McmvConvertResult(
      clientId: (json['clientId'] ?? json['client_id'])?.toString() ?? '',
      lead: rawLead is Map
          ? McmvLead.fromJson(Map<String, dynamic>.from(rawLead))
          : null,
    );
  }
}

// ─── Blacklist ───────────────────────────────────────────────────────────────

/// Entrada da blacklist — espelha `BlacklistEntry` do web.
class McmvBlacklistEntry {
  final String id;
  final String? cpf;
  final String? email;
  final String? phone;
  final String reason;
  final bool isPermanent;
  final DateTime? expiresAt;
  final String? createdByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const McmvBlacklistEntry({
    required this.id,
    this.cpf,
    this.email,
    this.phone,
    required this.reason,
    required this.isPermanent,
    this.expiresAt,
    this.createdByUserId,
    this.createdAt,
    this.updatedAt,
  });

  /// Bloqueio temporário cujo prazo já venceu.
  bool get isExpired =>
      !isPermanent &&
      expiresAt != null &&
      expiresAt!.isBefore(DateTime.now());

  factory McmvBlacklistEntry.fromJson(Map<String, dynamic> json) {
    return McmvBlacklistEntry(
      id: json['id']?.toString() ?? '',
      cpf: _toOptString(json['cpf']),
      email: _toOptString(json['email']),
      phone: _toOptString(json['phone']),
      reason: json['reason']?.toString() ?? '',
      isPermanent: _toBool(json['isPermanent'] ?? json['is_permanent']),
      expiresAt: _toDate(json['expiresAt'] ?? json['expires_at']),
      createdByUserId: _toOptString(
          json['createdByUserId'] ?? json['created_by_user_id']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Filtros de `GET /mcmv/blacklist` (cpf, email, phone, isPermanent, expired).
class McmvBlacklistFilters {
  final String? cpf;
  final String? email;
  final String? phone;
  final bool? isPermanent;
  final bool? expired;

  const McmvBlacklistFilters({
    this.cpf,
    this.email,
    this.phone,
    this.isPermanent,
    this.expired,
  });

  Map<String, String> toQueryParams() {
    final out = <String, String>{};
    final c = cpf?.trim();
    if (c != null && c.isNotEmpty) out['cpf'] = c;
    final e = email?.trim();
    if (e != null && e.isNotEmpty) out['email'] = e;
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) out['phone'] = p;
    if (isPermanent != null) {
      out['isPermanent'] = isPermanent! ? 'true' : 'false';
    }
    if (expired != null) out['expired'] = expired! ? 'true' : 'false';
    return out;
  }
}

/// Payload de `POST /mcmv/blacklist` — exige ao menos um identificador.
class McmvBlacklistCreateRequest {
  final String? cpf;
  final String? email;
  final String? phone;
  final String reason;
  final bool isPermanent;
  final DateTime? expiresAt;

  const McmvBlacklistCreateRequest({
    this.cpf,
    this.email,
    this.phone,
    required this.reason,
    this.isPermanent = false,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'reason': reason,
      'isPermanent': isPermanent,
    };
    final c = cpf?.trim();
    if (c != null && c.isNotEmpty) out['cpf'] = c;
    final e = email?.trim();
    if (e != null && e.isNotEmpty) out['email'] = e;
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) out['phone'] = p;
    if (!isPermanent && expiresAt != null) {
      out['expiresAt'] = expiresAt!.toUtc().toIso8601String();
    }
    return out;
  }
}

// ─── Templates ───────────────────────────────────────────────────────────────

/// Tipo do template (email/whatsapp/sms).
enum McmvTemplateType {
  email,
  whatsapp,
  sms,
  unknown;

  static McmvTemplateType fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'email':
        return McmvTemplateType.email;
      case 'whatsapp':
        return McmvTemplateType.whatsapp;
      case 'sms':
        return McmvTemplateType.sms;
      default:
        return McmvTemplateType.unknown;
    }
  }

  String get label {
    switch (this) {
      case McmvTemplateType.email:
        return 'Email';
      case McmvTemplateType.whatsapp:
        return 'WhatsApp';
      case McmvTemplateType.sms:
        return 'SMS';
      case McmvTemplateType.unknown:
        return 'Mensagem';
    }
  }
}

/// Template de mensagem MCMV — espelha `MCMVTemplate` do web. Templates sem
/// `companyId` são padrões do sistema (não podem ser removidos).
class McmvTemplate {
  final String id;
  final String name;
  final String content;
  final McmvTemplateType type;
  final String? companyId;
  final List<String> variables;
  final bool isActive;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const McmvTemplate({
    required this.id,
    required this.name,
    required this.content,
    required this.type,
    this.companyId,
    required this.variables,
    required this.isActive,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  bool get isSystemDefault => (companyId ?? '').isEmpty;

  /// Substitui `{{variavel}}` no conteúdo (paridade com
  /// `replaceTemplateVariables` do web).
  String contentWith(Map<String, String> values) {
    var out = content;
    values.forEach((key, value) {
      out = out.replaceAll(RegExp('{{\\s*$key\\s*}}'), value);
    });
    return out;
  }

  factory McmvTemplate.fromJson(Map<String, dynamic> json) {
    final rawVars = json['variables'];
    return McmvTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: McmvTemplateType.fromRaw(json['type']?.toString()),
      companyId: _toOptString(json['companyId'] ?? json['company_id']),
      variables: rawVars is List
          ? rawVars.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const [],
      isActive: json['isActive'] == null && json['is_active'] == null
          ? true
          : _toBool(json['isActive'] ?? json['is_active']),
      description: _toOptString(json['description']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}
