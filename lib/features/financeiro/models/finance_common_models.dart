/// Modelos comuns do módulo Financeiro (ERP União) + helpers de parse.
///
/// CONTRATO: shapes espelham 1:1 os tipos do imobx-front
/// (`src/types/financeiro.ts`) que por sua vez espelham o back financeiro-c3.
/// Campos monetários chegam como `number` OU `string` (Prisma.Decimal
/// serializa como string) — SEMPRE parse com [asDouble]/[asDoubleOrNull].
library;

// ─── Helpers de parse defensivo (usados por TODOS os models do módulo) ───────

/// Converte qualquer coisa em double (num, "12.5", "12,5", null → fallback).
double asDouble(dynamic v, [double fallback = 0]) =>
    asDoubleOrNull(v) ?? fallback;

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'));
  }
  return null;
}

int asInt(dynamic v, [int fallback = 0]) => asIntOrNull(v) ?? fallback;

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? asDoubleOrNull(v)?.toInt();
  return null;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

String asString(dynamic v, [String fallback = '']) =>
    asStringOrNull(v) ?? fallback;

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return v.toString();
}

/// Datas ISO do back ("2026-07-15" ou "2026-07-15T12:00:00.000Z").
DateTime? asDate(dynamic v) {
  final s = asStringOrNull(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

/// Map defensivo (jsonDecode pode devolver `Map` sem reificação).
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

Map<String, dynamic>? asMapOrNull(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Lista de maps defensiva — ignora itens que não são objetos.
List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Lista de strings defensiva.
List<String> asStringList(dynamic v) {
  if (v is! List) return const [];
  return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
}

/// Remove entradas null de um body antes do envio (padrão de todos os toJson
/// de payloads do módulo — o back usa ValidationPipe com whitelist).
Map<String, dynamic> compactBody(Map<String, dynamic> body) {
  body.removeWhere((_, value) => value == null);
  return body;
}

// ─── Referência enxuta { id, name } (objetos aninhados dos INCLUDEs) ──────────

/// Referência `{ id, name }` que o back inclui nas respostas (company,
/// supplier, category, broker, …). Sempre read-only.
class FinanceRef {
  final String id;
  final String name;

  const FinanceRef({required this.id, required this.name});

  factory FinanceRef.fromJson(Map<String, dynamic> json) => FinanceRef(
        id: asString(json['id']),
        name: asString(json['name'], asString(json['title'])),
      );

  static FinanceRef? fromJsonOrNull(dynamic json) {
    final map = asMapOrNull(json);
    if (map == null) return null;
    return FinanceRef.fromJson(map);
  }
}

// ─── Envelope paginado { data, total, page, pageSize } ────────────────────────

/// Envelope paginado do back financeiro. Vários GETs devolvem o envelope só
/// quando `page`+`pageSize` são enviados (sem eles, array nu) — o
/// [FinancePaginated.fromBody] tolera os dois formatos.
class FinancePaginated<T> {
  final List<T> data;
  final int total;
  final int page;
  final int pageSize;

  const FinancePaginated({
    required this.data,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < total;

  /// Aceita `{ data, total, page, pageSize }` OU array nu.
  factory FinancePaginated.fromBody(
    dynamic body,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    if (body is List) {
      final items = asMapList(body).map(itemFromJson).toList();
      return FinancePaginated(
        data: items,
        total: items.length,
        page: 1,
        pageSize: items.isEmpty ? 1 : items.length,
      );
    }
    final map = asMap(body);
    final items = asMapList(map['data']).map(itemFromJson).toList();
    return FinancePaginated(
      data: items,
      total: asInt(map['total'], items.length),
      page: asInt(map['page'], 1),
      pageSize: asInt(map['pageSize'], items.isEmpty ? 20 : items.length),
    );
  }
}

// ─── Empresa do Financeiro (GET /companies) ───────────────────────────────────

/// Empresa do microserviço financeiro. `types`: SALES | RENTAL | SERVICES.
class FinanceCompany {
  final String id;
  final String name;
  final String? document;
  final String? email;
  final String? phone;
  final List<String> types;
  final String? address;
  final String? responsible;
  final bool active;

  /// Vínculo com a empresa do CRM (fonte de verdade).
  final String? intellisysCompanyId;

  /// Unidade de venda no CRM (1 empresa CRM → várias no Financeiro).
  final String? intellisysSaleUnit;

  const FinanceCompany({
    required this.id,
    required this.name,
    this.document,
    this.email,
    this.phone,
    this.types = const [],
    this.address,
    this.responsible,
    this.active = true,
    this.intellisysCompanyId,
    this.intellisysSaleUnit,
  });

  factory FinanceCompany.fromJson(Map<String, dynamic> json) => FinanceCompany(
        id: asString(json['id']),
        name: asString(json['name']),
        document: asStringOrNull(json['document']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        types: asStringList(json['types']),
        address: asStringOrNull(json['address']),
        responsible: asStringOrNull(json['responsible']),
        active: asBool(json['active'], true),
        intellisysCompanyId: asStringOrNull(json['intellisysCompanyId']),
        intellisysSaleUnit: asStringOrNull(json['intellisysSaleUnit']),
      );

  static List<FinanceCompany> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceCompany.fromJson).toList();
}

/// Payload de POST /companies e PATCH /companies/:id.
class FinanceCompanyInput {
  final String? name;
  final String? document;
  final List<String>? types;
  final String? phone;
  final String? email;
  final String? address;
  final String? responsible;
  final bool? active;
  final String? intellisysCompanyId;
  final String? intellisysSaleUnit;

  const FinanceCompanyInput({
    this.name,
    this.document,
    this.types,
    this.phone,
    this.email,
    this.address,
    this.responsible,
    this.active,
    this.intellisysCompanyId,
    this.intellisysSaleUnit,
  });

  Map<String, dynamic> toJson() => compactBody({
        'name': name,
        'document': document,
        'types': types,
        'phone': phone,
        'email': email,
        'address': address,
        'responsible': responsible,
        'active': active,
        'intellisysCompanyId': intellisysCompanyId,
        'intellisysSaleUnit': intellisysSaleUnit,
      });
}

// ─── Identidade no módulo (GET /auth/me do microserviço) ─────────────────────

/// Papéis do módulo Financeiro (matriz papel×tela da reunião 14/07).
/// Guardado como String crua para tolerar papéis novos do back.
class FinanceRoles {
  FinanceRoles._();

  static const admin = 'ADMIN';
  static const diretorFinanceiro = 'DIRETOR_FINANCEIRO';
  static const gerenteFinanceiro = 'GERENTE_FINANCEIRO';
  static const analistaFinanceiro = 'ANALISTA_FINANCEIRO';
  static const rh = 'RH';
  static const gestorMarketing = 'GESTOR_MARKETING';

  /// Legado (migrado para ANALISTA_FINANCEIRO no back).
  static const financeiro = 'FINANCEIRO';
  static const diretor = 'DIRETOR';
  static const gestor = 'GESTOR';
  static const corretor = 'CORRETOR';
}

/// GET /auth/me (microserviço financeiro) — papel/vínculo LOCAL do módulo.
/// `linked == false` = usuário do CRM ainda sem vínculo no Financeiro
/// (modo transição: tratar como "sem gating por papel").
/// Back antigo responde 404 — o chamador trata como "sem gating".
class FinanceMe {
  final bool linked;
  final String? userId;
  final String? name;
  final String email;
  final String role;
  final List<FinanceRef> companies;

  const FinanceMe({
    required this.linked,
    this.userId,
    this.name,
    required this.email,
    required this.role,
    this.companies = const [],
  });

  bool get isAdmin => role == FinanceRoles.admin;

  factory FinanceMe.fromJson(Map<String, dynamic> json) => FinanceMe(
        linked: asBool(json['linked']),
        userId: asStringOrNull(json['userId']),
        name: asStringOrNull(json['name']),
        email: asString(json['email']),
        role: asString(json['role'], FinanceRoles.corretor),
        companies: asMapList(json['companies'])
            .map(FinanceRef.fromJson)
            .toList(),
      );
}

// ─── Trilha de auditoria (GET /audit-logs) ────────────────────────────────────

/// Registro de auditoria. `action` já vem como frase legível em pt-BR
/// (ex.: "Conta a pagar criada"); `before`/`after` trazem o diff.
class FinanceAuditLog {
  final String id;
  final String companyId;
  final String userId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final DateTime? createdAt;
  final FinanceRef? user;

  const FinanceAuditLog({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.before,
    this.after,
    this.createdAt,
    this.user,
  });

  factory FinanceAuditLog.fromJson(Map<String, dynamic> json) =>
      FinanceAuditLog(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        userId: asString(json['userId']),
        action: asString(json['action']),
        entityType: asString(json['entityType']),
        entityId: asString(json['entityId']),
        before: asMapOrNull(json['before']),
        after: asMapOrNull(json['after']),
        createdAt: asDate(json['createdAt']),
        user: FinanceRef.fromJsonOrNull(json['user']),
      );

  static List<FinanceAuditLog> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceAuditLog.fromJson).toList();
}
