/// Modelos de Fichas de Locação — espelha `rentalApplicationFormsApi.ts`
/// (imobx-front) e a tabela `rental_application_forms` do backend.
///
/// O `payload` é um JSON com três blocos de texto livre por seção
/// (`inquilino`, `fiador`, `proprietario` — `Map<String, String>`) e
/// `observacoesInternas`. Não há colunas tipadas por campo: o app grava as
/// mesmas chaves/máscaras do web (`RentalLocacaoFormBody.tsx`) para manter o
/// PDF e a página pública 100% compatíveis.
library;

/// Permissões do domínio (strings exatas do web — `fichas.routes.tsx` +
/// `permission.enum.ts`). Mantidas aqui porque `app_permissions.dart` é
/// compartilhado e a fiação é central.
class RentalFormPermissions {
  RentalFormPermissions._();

  /// Módulo da empresa exigido pela rota web (`requiredModule`).
  static const String module = 'rental_management';

  static const String view = 'rental_form:view';
  static const String viewTeam = 'rental_form:view_team';
  static const String viewAll = 'rental_form:view_all';
  static const String create = 'rental_form:create';
  static const String update = 'rental_form:update';
  static const String delete = 'rental_form:delete';
  static const String export = 'rental_form:export';

  /// Qualquer visão libera a entrada no drawer (paridade com o gating web).
  static const List<String> menu = [view, viewTeam, viewAll];
}

/// Status da ficha (coluna `status`).
enum RentalFormStatus { pending, awaitingSignature, canceled, finalized }

extension RentalFormStatusX on RentalFormStatus {
  String get apiValue {
    switch (this) {
      case RentalFormStatus.pending:
        return 'pending';
      case RentalFormStatus.awaitingSignature:
        return 'awaiting_signature';
      case RentalFormStatus.canceled:
        return 'canceled';
      case RentalFormStatus.finalized:
        return 'finalized';
    }
  }

  String get label {
    switch (this) {
      case RentalFormStatus.pending:
        return 'Pendente';
      case RentalFormStatus.awaitingSignature:
        return 'Aguardando assinatura';
      case RentalFormStatus.canceled:
        return 'Cancelada';
      case RentalFormStatus.finalized:
        return 'Finalizada';
    }
  }

  /// Rótulo curto para chips/badges.
  String get shortLabel {
    switch (this) {
      case RentalFormStatus.pending:
        return 'Pendentes';
      case RentalFormStatus.awaitingSignature:
        return 'Aguardando';
      case RentalFormStatus.canceled:
        return 'Canceladas';
      case RentalFormStatus.finalized:
        return 'Finalizadas';
    }
  }
}

RentalFormStatus parseRentalFormStatus(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim();
  switch (s) {
    case 'awaiting_signature':
      return RentalFormStatus.awaitingSignature;
    case 'canceled':
    case 'cancelled':
      return RentalFormStatus.canceled;
    case 'finalized':
      return RentalFormStatus.finalized;
    default:
      // Inclui o legado 'draft' (default da tabela) → tratamos como pendente.
      return RentalFormStatus.pending;
  }
}

/// Tipo do link público — o cliente abre a ficha completa ou apenas um bloco.
enum RentalPublicLinkType { completa, inquilino, fiador, proprietario }

extension RentalPublicLinkTypeX on RentalPublicLinkType {
  String get apiValue {
    switch (this) {
      case RentalPublicLinkType.completa:
        return 'completa';
      case RentalPublicLinkType.inquilino:
        return 'inquilino';
      case RentalPublicLinkType.fiador:
        return 'fiador';
      case RentalPublicLinkType.proprietario:
        return 'proprietario';
    }
  }

  String get label {
    switch (this) {
      case RentalPublicLinkType.completa:
        return 'Ficha completa';
      case RentalPublicLinkType.inquilino:
        return 'Somente inquilino';
      case RentalPublicLinkType.fiador:
        return 'Somente fiador';
      case RentalPublicLinkType.proprietario:
        return 'Somente proprietário';
    }
  }
}

/// Usuário resumido (criador / envolvidos).
class RentalFormUser {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  const RentalFormUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory RentalFormUser.fromJson(Map<String, dynamic> j) => RentalFormUser(
        id: _str(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        avatar: _strNull(j['avatar']),
      );

  String get initials {
    final safe = name.trim();
    if (safe.isEmpty) return '?';
    return safe
        .split(RegExp(r'\s+'))
        .take(2)
        .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
        .join();
  }
}

/// Evento do histórico de assinaturas (`signatureHistory`).
class RentalSignatureEvent {
  final String id;

  /// 'sent' | 'signed' | 'canceled'
  final String eventType;
  final String? signatureUrl;
  final String? actorUserName;
  final DateTime? createdAt;

  const RentalSignatureEvent({
    required this.id,
    required this.eventType,
    this.signatureUrl,
    this.actorUserName,
    this.createdAt,
  });

  factory RentalSignatureEvent.fromJson(Map<String, dynamic> j) =>
      RentalSignatureEvent(
        id: _str(j['id']),
        eventType: _str(j['eventType']).toLowerCase(),
        signatureUrl: _strNull(j['signatureUrl']),
        actorUserName: _strNull(j['actorUserName']),
        createdAt: _date(j['createdAt']),
      );

  String get label {
    switch (eventType) {
      case 'signed':
        return 'Assinado';
      case 'canceled':
        return 'Cancelado';
      default:
        return 'Enviado';
    }
  }
}

/// Ficha de locação — guarda o `raw` (como o `SaleForm`) com getters tipados
/// nos campos usados pela UI. Parse defensivo (null/string/number tolerante).
class RentalForm {
  final Map<String, dynamic> raw;
  const RentalForm(this.raw);

  factory RentalForm.fromJson(Map<String, dynamic> j) =>
      RentalForm(Map<String, dynamic>.from(j));

  String get id => _str(raw['id']);
  String? get title => _strNull(raw['title']);
  RentalFormStatus get status => parseRentalFormStatus(raw['status']);

  String get createdById =>
      _str(raw['createdById'] ?? raw['created_by_id']);

  RentalFormUser? get createdBy {
    final u = raw['createdBy'] ?? raw['created_by'];
    if (u is Map) return RentalFormUser.fromJson(Map<String, dynamic>.from(u));
    return null;
  }

  List<RentalFormUser> get involvedUsers {
    final list = raw['involvedUsers'] ?? raw['involved_users'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => RentalFormUser.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  String? get publicToken =>
      _strNull(raw['publicToken'] ?? raw['public_token']);
  DateTime? get publicTokenExpiresAt =>
      _date(raw['publicTokenExpiresAt'] ?? raw['public_token_expires_at']);
  DateTime? get submittedAt =>
      _date(raw['submittedAt'] ?? raw['submitted_at']);
  String? get signatureUrl =>
      _strNull(raw['signatureUrl'] ?? raw['signature_url']);

  List<RentalSignatureEvent> get signatureHistory {
    final list = raw['signatureHistory'] ?? raw['signature_history'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) =>
            RentalSignatureEvent.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  DateTime? get createdAt => _date(raw['createdAt'] ?? raw['created_at']);
  DateTime? get updatedAt => _date(raw['updatedAt'] ?? raw['updated_at']);

  // ── Payload (blocos da ficha) ────────────────────────────────────────────

  Map<String, dynamic> get payload {
    final p = raw['payload'];
    if (p is Map) return Map<String, dynamic>.from(p);
    return const {};
  }

  /// Bloco de uma seção (`inquilino`/`fiador`/`proprietario`) como
  /// `Map<String, String>` — tolerante a valores não-string.
  Map<String, String> section(String key) {
    final s = payload[key];
    if (s is! Map) return const {};
    final out = <String, String>{};
    s.forEach((k, v) {
      if (v == null) return;
      out[k.toString()] = v.toString();
    });
    return out;
  }

  String get observacoesInternas =>
      _str(payload['observacoesInternas']);

  /// Nome exibido do responsável (criador).
  String get responsibleName {
    final byName = createdBy?.name.trim();
    if (byName != null && byName.isNotEmpty) return byName;
    return 'Responsável';
  }
}

/// Resultado da listagem (`GET /sistema/fichas-locacao`).
class RentalFormListResult {
  final List<RentalForm> items;
  final int total;
  final int page;
  final int limit;

  const RentalFormListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
}

/// Retorno de `POST /:id/link-publico`.
class RentalPublicLink {
  final String token;
  final DateTime? expiresAt;
  const RentalPublicLink({required this.token, this.expiresAt});

  factory RentalPublicLink.fromJson(Map<String, dynamic> j) =>
      RentalPublicLink(token: _str(j['token']), expiresAt: _date(j['expiresAt']));
}

/// Retorno de `POST /:id/assinatura-link`.
class RentalSignatureLink {
  final String signatureUrl;
  final String token;
  final DateTime? expiresAt;
  const RentalSignatureLink({
    required this.signatureUrl,
    required this.token,
    this.expiresAt,
  });

  factory RentalSignatureLink.fromJson(Map<String, dynamic> j) =>
      RentalSignatureLink(
        signatureUrl: _str(j['signatureUrl']),
        token: _str(j['token']),
        expiresAt: _date(j['expiresAt']),
      );
}

// ─── Helpers de parse ───────────────────────────────────────────────────────

String _str(dynamic v) => v?.toString() ?? '';

String? _strNull(dynamic v) {
  final s = v?.toString();
  if (s == null || s.trim().isEmpty) return null;
  return s;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
