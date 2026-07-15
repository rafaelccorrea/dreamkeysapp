// Modelos do módulo de Locações — espelham `rental.types.ts` do imobx-front
// e as respostas do `RentalController` (NestJS): `GET /rental`,
// `GET /rental/:id`, `GET /rental/:id/payments`, `GET /rental/:id/history`,
// `GET /rental/:id/comments` e `GET /rental/dashboard/stats`.

/// Permissões / módulo do domínio de locações — strings exatas do web
/// (`imobx-front/src/routes/domains/rentals.routes.tsx`).
class RentalPermissions {
  RentalPermissions._();

  static const String module = 'rental_management';
  static const String view = 'rental:view';
  static const String create = 'rental:create';
  static const String update = 'rental:update';
  static const String delete = 'rental:delete';
  static const String viewDashboard = 'rental:view_dashboard';
  static const String managePayments = 'rental:manage_payments';
  static const String manageWorkflows = 'rental:manage_workflows';
  static const String viewFinancials = 'rental:view_financials';
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  }
  return 0;
}

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.trim().isEmpty) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }
  return null;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

// ─── Status da locação ───────────────────────────────────────────────────────

/// Status do contrato (1:1 com `RentalStatus` do backend/web).
enum RentalStatus {
  active,
  pending,
  pendingApproval,
  expired,
  cancelled,
  unknown;

  static RentalStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'active':
        return RentalStatus.active;
      case 'pending':
        return RentalStatus.pending;
      case 'pending_approval':
        return RentalStatus.pendingApproval;
      case 'expired':
        return RentalStatus.expired;
      case 'cancelled':
      case 'canceled':
        return RentalStatus.cancelled;
      default:
        return RentalStatus.unknown;
    }
  }

  /// Valor exato enviado à API.
  String get apiValue {
    switch (this) {
      case RentalStatus.active:
        return 'active';
      case RentalStatus.pending:
        return 'pending';
      case RentalStatus.pendingApproval:
        return 'pending_approval';
      case RentalStatus.expired:
        return 'expired';
      case RentalStatus.cancelled:
        return 'cancelled';
      case RentalStatus.unknown:
        return '';
    }
  }

  String get label {
    switch (this) {
      case RentalStatus.active:
        return 'Ativo';
      case RentalStatus.pending:
        return 'Pendente';
      case RentalStatus.pendingApproval:
        return 'Aguardando aprovação';
      case RentalStatus.expired:
        return 'Expirado';
      case RentalStatus.cancelled:
        return 'Cancelado';
      case RentalStatus.unknown:
        return 'Locação';
    }
  }

  /// Opções selecionáveis no app (mesma lista de `RentalStatusLabels` do web).
  static const List<RentalStatus> selectable = [
    RentalStatus.active,
    RentalStatus.pending,
    RentalStatus.pendingApproval,
    RentalStatus.expired,
    RentalStatus.cancelled,
  ];
}

// ─── Status / método de pagamento ───────────────────────────────────────────

enum RentalPaymentStatus {
  pending,
  paid,
  overdue,
  cancelled,
  partial,
  unknown;

  static RentalPaymentStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return RentalPaymentStatus.pending;
      case 'paid':
        return RentalPaymentStatus.paid;
      case 'overdue':
        return RentalPaymentStatus.overdue;
      case 'cancelled':
      case 'canceled':
        return RentalPaymentStatus.cancelled;
      case 'partial':
        return RentalPaymentStatus.partial;
      default:
        return RentalPaymentStatus.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case RentalPaymentStatus.pending:
        return 'pending';
      case RentalPaymentStatus.paid:
        return 'paid';
      case RentalPaymentStatus.overdue:
        return 'overdue';
      case RentalPaymentStatus.cancelled:
        return 'cancelled';
      case RentalPaymentStatus.partial:
        return 'partial';
      case RentalPaymentStatus.unknown:
        return '';
    }
  }

  String get label {
    switch (this) {
      case RentalPaymentStatus.pending:
        return 'Pendente';
      case RentalPaymentStatus.paid:
        return 'Pago';
      case RentalPaymentStatus.overdue:
        return 'Atrasado';
      case RentalPaymentStatus.cancelled:
        return 'Cancelado';
      case RentalPaymentStatus.partial:
        return 'Parcial';
      case RentalPaymentStatus.unknown:
        return 'Pagamento';
    }
  }
}

enum RentalPaymentMethod {
  cash,
  pix,
  bankTransfer,
  creditCard,
  debitCard,
  check,
  bankSlip,
  other;

  static RentalPaymentMethod? fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'cash':
        return RentalPaymentMethod.cash;
      case 'pix':
        return RentalPaymentMethod.pix;
      case 'bank_transfer':
        return RentalPaymentMethod.bankTransfer;
      case 'credit_card':
        return RentalPaymentMethod.creditCard;
      case 'debit_card':
        return RentalPaymentMethod.debitCard;
      case 'check':
        return RentalPaymentMethod.check;
      case 'bank_slip':
        return RentalPaymentMethod.bankSlip;
      case 'other':
        return RentalPaymentMethod.other;
      default:
        return null;
    }
  }

  String get apiValue {
    switch (this) {
      case RentalPaymentMethod.cash:
        return 'cash';
      case RentalPaymentMethod.pix:
        return 'pix';
      case RentalPaymentMethod.bankTransfer:
        return 'bank_transfer';
      case RentalPaymentMethod.creditCard:
        return 'credit_card';
      case RentalPaymentMethod.debitCard:
        return 'debit_card';
      case RentalPaymentMethod.check:
        return 'check';
      case RentalPaymentMethod.bankSlip:
        return 'bank_slip';
      case RentalPaymentMethod.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case RentalPaymentMethod.cash:
        return 'Dinheiro';
      case RentalPaymentMethod.pix:
        return 'PIX';
      case RentalPaymentMethod.bankTransfer:
        return 'Transferência Bancária';
      case RentalPaymentMethod.creditCard:
        return 'Cartão de Crédito';
      case RentalPaymentMethod.debitCard:
        return 'Cartão de Débito';
      case RentalPaymentMethod.check:
        return 'Cheque';
      case RentalPaymentMethod.bankSlip:
        return 'Boleto Bancário';
      case RentalPaymentMethod.other:
        return 'Outro';
    }
  }
}

// ─── Imóvel resumido (relation `property` da locação) ────────────────────────

class RentalProperty {
  final String id;
  final String title;
  final String? code;
  final String? type;
  final String? address;
  final String? street;
  final String? number;
  final String? neighborhood;
  final String? city;
  final String? state;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? totalArea;
  final String? mainImageUrl;

  const RentalProperty({
    required this.id,
    required this.title,
    this.code,
    this.type,
    this.address,
    this.street,
    this.number,
    this.neighborhood,
    this.city,
    this.state,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.totalArea,
    this.mainImageUrl,
  });

  String get typeLabel {
    switch ((type ?? '').toLowerCase()) {
      case 'house':
        return 'Casa';
      case 'apartment':
        return 'Apartamento';
      case 'commercial':
        return 'Comercial';
      case 'land':
        return 'Terreno';
      case 'rural':
        return 'Rural';
      default:
        return 'Imóvel';
    }
  }

  /// Endereço amigável — rua/número/bairro/cidade quando disponível.
  String? get locationLabel {
    final parts = <String>[];
    final s = (street ?? '').trim();
    final n = (number ?? '').trim();
    if (s.isNotEmpty) parts.add(n.isNotEmpty ? '$s, $n' : s);
    final b = (neighborhood ?? '').trim();
    if (b.isNotEmpty) parts.add(b);
    final c = (city ?? '').trim();
    final uf = (state ?? '').trim();
    if (c.isNotEmpty) parts.add(uf.isNotEmpty ? '$c - $uf' : c);
    if (parts.isEmpty) {
      final a = (address ?? '').trim();
      return a.isEmpty ? null : a;
    }
    return parts.join(' · ');
  }

  factory RentalProperty.fromJson(Map<String, dynamic> json) {
    final mainImage = _asMap(json['mainImage']);
    return RentalProperty(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      code: json['code']?.toString(),
      type: json['type']?.toString(),
      address: json['address']?.toString(),
      street: json['street']?.toString(),
      number: json['number']?.toString(),
      neighborhood: json['neighborhood']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      bedrooms: json['bedrooms'] == null ? null : _toInt(json['bedrooms']),
      bathrooms: json['bathrooms'] == null ? null : _toInt(json['bathrooms']),
      parkingSpaces:
          json['parkingSpaces'] == null ? null : _toInt(json['parkingSpaces']),
      totalArea: _toDoubleOrNull(json['totalArea']),
      mainImageUrl: mainImage?['fileUrl']?.toString(),
    );
  }
}

// ─── Pagamento (parcela) ─────────────────────────────────────────────────────

class RentalPayment {
  final String id;
  final DateTime? dueDate;
  final DateTime? paymentDate;
  final double value;
  final double? paidValue;
  final double? discountValue;
  final double? interestValue;
  final double? fineValue;
  final RentalPaymentStatus status;
  final RentalPaymentMethod? paymentMethod;
  final String referenceMonth;
  final String? observations;
  final String? asaasPaymentId;
  final String? asaasInvoiceUrl;
  final String? asaasBankSlipUrl;
  final String? asaasPixCopyPaste;

  const RentalPayment({
    required this.id,
    this.dueDate,
    this.paymentDate,
    required this.value,
    this.paidValue,
    this.discountValue,
    this.interestValue,
    this.fineValue,
    required this.status,
    this.paymentMethod,
    required this.referenceMonth,
    this.observations,
    this.asaasPaymentId,
    this.asaasInvoiceUrl,
    this.asaasBankSlipUrl,
    this.asaasPixCopyPaste,
  });

  bool get isPaid => status == RentalPaymentStatus.paid;
  bool get hasCharge =>
      (asaasPaymentId ?? '').isNotEmpty || (asaasInvoiceUrl ?? '').isNotEmpty;

  /// Está vencida (pendente com vencimento no passado) ou marcada `overdue`.
  bool get isLate {
    if (status == RentalPaymentStatus.overdue) return true;
    if (status != RentalPaymentStatus.pending) return false;
    final d = dueDate;
    if (d == null) return false;
    final today = DateTime.now();
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  factory RentalPayment.fromJson(Map<String, dynamic> json) {
    return RentalPayment(
      id: json['id']?.toString() ?? '',
      dueDate: _toDate(json['dueDate'] ?? json['due_date']),
      paymentDate: _toDate(json['paymentDate'] ?? json['payment_date']),
      value: _toDouble(json['value']),
      paidValue: _toDoubleOrNull(json['paidValue'] ?? json['paid_value']),
      discountValue:
          _toDoubleOrNull(json['discountValue'] ?? json['discount_value']),
      interestValue:
          _toDoubleOrNull(json['interestValue'] ?? json['interest_value']),
      fineValue: _toDoubleOrNull(json['fineValue'] ?? json['fine_value']),
      status: RentalPaymentStatus.fromRaw(json['status']?.toString()),
      paymentMethod: RentalPaymentMethod.fromRaw(
          (json['paymentMethod'] ?? json['payment_method'])?.toString()),
      referenceMonth:
          (json['referenceMonth'] ?? json['reference_month'])?.toString() ??
              '',
      observations: json['observations']?.toString(),
      asaasPaymentId: json['asaasPaymentId']?.toString(),
      asaasInvoiceUrl: json['asaasInvoiceUrl']?.toString(),
      asaasBankSlipUrl: json['asaasBankSlipUrl']?.toString(),
      asaasPixCopyPaste: json['asaasPixCopyPaste']?.toString(),
    );
  }
}

// ─── Locação ─────────────────────────────────────────────────────────────────

class Rental {
  final String id;
  final String tenantName;
  final String tenantDocument;
  final String? tenantPhone;
  final String? tenantEmail;
  final DateTime? startDate;
  final DateTime? endDate;
  final double monthlyValue;
  final int dueDay;
  final RentalStatus status;
  final String? observations;
  final double? depositValue;
  final bool autoGeneratePayments;
  final String propertyId;
  final RentalProperty? property;
  final List<RentalPayment> payments;
  final double? lateFeePercent;
  final double? interestPerMonthPercent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Rental({
    required this.id,
    required this.tenantName,
    required this.tenantDocument,
    this.tenantPhone,
    this.tenantEmail,
    this.startDate,
    this.endDate,
    required this.monthlyValue,
    required this.dueDay,
    required this.status,
    this.observations,
    this.depositValue,
    required this.autoGeneratePayments,
    required this.propertyId,
    this.property,
    this.payments = const [],
    this.lateFeePercent,
    this.interestPerMonthPercent,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPendingApproval => status == RentalStatus.pendingApproval;

  /// Contrato vence nos próximos 30 dias (e ainda está ativo).
  bool get isExpiringSoon {
    if (status != RentalStatus.active) return false;
    final end = endDate;
    if (end == null) return false;
    final now = DateTime.now();
    final diff = end.difference(now).inDays;
    return diff >= 0 && diff <= 30;
  }

  /// CPF/CNPJ formatado para exibição.
  String get tenantDocumentMasked {
    final digits = tenantDocument.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.'
          '${digits.substring(6, 9)}-${digits.substring(9)}';
    }
    if (digits.length == 14) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.'
          '${digits.substring(5, 8)}/${digits.substring(8, 12)}-'
          '${digits.substring(12)}';
    }
    return tenantDocument;
  }

  String get tenantPhoneMasked {
    final digits = (tenantPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-'
          '${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-'
          '${digits.substring(6)}';
    }
    return tenantPhone ?? '';
  }

  factory Rental.fromJson(Map<String, dynamic> json) {
    final property = _asMap(json['property']);
    final paymentsRaw = json['payments'];
    return Rental(
      id: json['id']?.toString() ?? '',
      tenantName:
          (json['tenantName'] ?? json['tenant_name'])?.toString() ?? '',
      tenantDocument:
          (json['tenantDocument'] ?? json['tenant_document'])?.toString() ??
              '',
      tenantPhone: (json['tenantPhone'] ?? json['tenant_phone'])?.toString(),
      tenantEmail: (json['tenantEmail'] ?? json['tenant_email'])?.toString(),
      startDate: _toDate(json['startDate'] ?? json['start_date']),
      endDate: _toDate(json['endDate'] ?? json['end_date']),
      monthlyValue: _toDouble(json['monthlyValue'] ?? json['monthly_value']),
      dueDay: _toInt(json['dueDay'] ?? json['due_day'], 5),
      status: RentalStatus.fromRaw(json['status']?.toString()),
      observations: json['observations']?.toString(),
      depositValue:
          _toDoubleOrNull(json['depositValue'] ?? json['deposit_value']),
      autoGeneratePayments: _toBool(
          json['autoGeneratePayments'] ?? json['auto_generate_payments'],
          true),
      propertyId:
          (json['propertyId'] ?? json['property_id'])?.toString() ?? '',
      property: property != null ? RentalProperty.fromJson(property) : null,
      payments: paymentsRaw is List
          ? paymentsRaw
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .map(RentalPayment.fromJson)
              .toList()
          : const [],
      lateFeePercent:
          _toDoubleOrNull(json['lateFeePercent'] ?? json['late_fee_percent']),
      interestPerMonthPercent: _toDoubleOrNull(json['interestPerMonthPercent'] ??
          json['interest_per_month_percent']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

// ─── Lista paginada ──────────────────────────────────────────────────────────

class RentalListResult {
  final List<Rental> rentals;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const RentalListResult({
    required this.rentals,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const empty = RentalListResult(
    rentals: [],
    total: 0,
    page: 1,
    limit: 20,
    totalPages: 1,
  );

  factory RentalListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['rentals'] ?? json['data'];
    final list = raw is List
        ? raw
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map(Rental.fromJson)
            .toList()
        : <Rental>[];
    return RentalListResult(
      rentals: list,
      total: _toInt(json['total'], list.length),
      page: _toInt(json['page'], 1),
      limit: _toInt(json['limit'], 20),
      totalPages: _toInt(json['totalPages'], 1),
    );
  }
}

// ─── Filtros de listagem (query de GET /rental) ──────────────────────────────

class RentalFilters {
  final String? propertyId;
  final RentalStatus? status;
  final String? tenantName;
  final String? tenantDocument;
  final String? search;

  /// Datas em `yyyy-MM-dd` (mesmo formato do web).
  final String? startDateFrom;
  final String? startDateTo;
  final int page;
  final int limit;

  const RentalFilters({
    this.propertyId,
    this.status,
    this.tenantName,
    this.tenantDocument,
    this.search,
    this.startDateFrom,
    this.startDateTo,
    this.page = 1,
    this.limit = 20,
  });

  /// Quantos filtros "avançados" estão ativos (fora status/busca/página).
  int get advancedCount {
    var n = 0;
    if ((tenantName ?? '').trim().isNotEmpty) n++;
    if ((tenantDocument ?? '').trim().isNotEmpty) n++;
    if ((startDateFrom ?? '').isNotEmpty) n++;
    if ((startDateTo ?? '').isNotEmpty) n++;
    if ((propertyId ?? '').isNotEmpty) n++;
    return n;
  }

  RentalFilters copyWith({
    String? propertyId,
    RentalStatus? status,
    String? tenantName,
    String? tenantDocument,
    String? search,
    String? startDateFrom,
    String? startDateTo,
    int? page,
    int? limit,
    bool clearStatus = false,
    bool clearAdvanced = false,
  }) {
    return RentalFilters(
      propertyId:
          clearAdvanced ? null : (propertyId ?? this.propertyId),
      status: clearStatus ? null : (status ?? this.status),
      tenantName: clearAdvanced ? null : (tenantName ?? this.tenantName),
      tenantDocument:
          clearAdvanced ? null : (tenantDocument ?? this.tenantDocument),
      search: search ?? this.search,
      startDateFrom:
          clearAdvanced ? null : (startDateFrom ?? this.startDateFrom),
      startDateTo: clearAdvanced ? null : (startDateTo ?? this.startDateTo),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if ((propertyId ?? '').isNotEmpty) out['propertyId'] = propertyId!;
    if (status != null && status != RentalStatus.unknown) {
      out['status'] = status!.apiValue;
    }
    final tn = tenantName?.trim();
    if (tn != null && tn.isNotEmpty) out['tenantName'] = tn;
    final td = tenantDocument?.replaceAll(RegExp(r'\D'), '');
    if (td != null && td.isNotEmpty) out['tenantDocument'] = td;
    final s = search?.trim();
    if (s != null && s.isNotEmpty) out['search'] = s;
    if ((startDateFrom ?? '').isNotEmpty) out['startDateFrom'] = startDateFrom!;
    if ((startDateTo ?? '').isNotEmpty) out['startDateTo'] = startDateTo!;
    return out;
  }
}

// ─── Histórico e comentários ─────────────────────────────────────────────────

class RentalHistoryEntry {
  final String id;
  final String action;
  final String? description;
  final DateTime? createdAt;
  final String? userName;

  const RentalHistoryEntry({
    required this.id,
    required this.action,
    this.description,
    this.createdAt,
    this.userName,
  });

  /// Rótulo pt-BR da ação (mesma tabela do `RentalDetailsPage.tsx`).
  String get actionLabel {
    const labels = <String, String>{
      'created': 'Locação criada',
      'updated': 'Locação atualizada',
      'approved': 'Locação aprovada',
      'rejected': 'Locação rejeitada',
      'cancelled': 'Locação excluída',
      'status_changed': 'Status alterado',
      'payment_added': 'Pagamento adicionado',
      'payment_updated': 'Pagamento atualizado',
      'payments_generated': 'Pagamentos gerados',
      'charge_updated': 'Cobrança editada',
      'charge_generated': 'Cobrança gerada',
      'charge_cancelled': 'Cobrança cancelada',
      'marked_paid': 'Marcado como pago',
      'payment_deleted': 'Pagamento excluído',
      'comment_added': 'Comentário adicionado',
    };
    return labels[action] ?? action;
  }

  factory RentalHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RentalHistoryEntry(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      description: json['description']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      userName: (json['userName'] ?? json['user_name'])?.toString(),
    );
  }
}

class RentalCommentEntry {
  final String id;
  final String content;
  final DateTime? createdAt;
  final String? userName;

  const RentalCommentEntry({
    required this.id,
    required this.content,
    this.createdAt,
    this.userName,
  });

  factory RentalCommentEntry.fromJson(Map<String, dynamic> json) {
    return RentalCommentEntry(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      userName: (json['userName'] ?? json['user_name'])?.toString(),
    );
  }
}

/// Página genérica `{ items, total, page, limit, totalPages }`.
class RentalPagedResult<T> {
  final List<T> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const RentalPagedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;

  factory RentalPagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final raw = json['items'] ?? json['data'];
    final list = raw is List
        ? raw
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map(itemFromJson)
            .toList()
        : <T>[];
    return RentalPagedResult<T>(
      items: list,
      total: _toInt(json['total'], list.length),
      page: _toInt(json['page'], 1),
      limit: _toInt(json['limit'], 10),
      totalPages: _toInt(json['totalPages'], 1),
    );
  }
}

// ─── Dashboard ───────────────────────────────────────────────────────────────

class RentalDashboardRecent {
  final String id;
  final String tenantName;
  final String propertyAddress;
  final double monthlyValue;
  final DateTime? startDate;
  final RentalStatus status;

  const RentalDashboardRecent({
    required this.id,
    required this.tenantName,
    required this.propertyAddress,
    required this.monthlyValue,
    this.startDate,
    required this.status,
  });

  factory RentalDashboardRecent.fromJson(Map<String, dynamic> json) {
    return RentalDashboardRecent(
      id: json['id']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? '',
      propertyAddress: json['propertyAddress']?.toString() ?? '',
      monthlyValue: _toDouble(json['monthlyValue']),
      startDate: _toDate(json['startDate']),
      status: RentalStatus.fromRaw(json['status']?.toString()),
    );
  }
}

class RentalPaymentsByStatus {
  final RentalPaymentStatus status;
  final int count;
  final double totalValue;

  const RentalPaymentsByStatus({
    required this.status,
    required this.count,
    required this.totalValue,
  });

  factory RentalPaymentsByStatus.fromJson(Map<String, dynamic> json) {
    return RentalPaymentsByStatus(
      status: RentalPaymentStatus.fromRaw(json['status']?.toString()),
      count: _toInt(json['count']),
      totalValue: _toDouble(json['totalValue']),
    );
  }
}

class RentalMonthlyRevenuePoint {
  final String month;
  final double revenue;
  final double paid;
  final double pending;

  const RentalMonthlyRevenuePoint({
    required this.month,
    required this.revenue,
    required this.paid,
    required this.pending,
  });

  factory RentalMonthlyRevenuePoint.fromJson(Map<String, dynamic> json) {
    return RentalMonthlyRevenuePoint(
      month: json['month']?.toString() ?? '',
      revenue: _toDouble(json['revenue']),
      paid: _toDouble(json['paid']),
      pending: _toDouble(json['pending']),
    );
  }
}

/// Resposta de `GET /rental/dashboard/stats` (paridade com
/// `rentalDashboardService.ts`).
class RentalDashboardData {
  final int totalRentals;
  final int activeRentals;
  final int expiredRentals;
  final int pendingRentals;
  final double totalMonthlyRevenue;
  final double paidThisMonth;
  final double pendingThisMonth;
  final int overduePayments;
  final double occupancyRate;
  final double averageRentalValue;
  final int expiringContracts;
  final List<RentalDashboardRecent> recentRentals;
  final List<RentalPaymentsByStatus> paymentsByStatus;
  final List<RentalMonthlyRevenuePoint> monthlyRevenueChart;

  const RentalDashboardData({
    required this.totalRentals,
    required this.activeRentals,
    required this.expiredRentals,
    required this.pendingRentals,
    required this.totalMonthlyRevenue,
    required this.paidThisMonth,
    required this.pendingThisMonth,
    required this.overduePayments,
    required this.occupancyRate,
    required this.averageRentalValue,
    required this.expiringContracts,
    required this.recentRentals,
    required this.paymentsByStatus,
    required this.monthlyRevenueChart,
  });

  static const zero = RentalDashboardData(
    totalRentals: 0,
    activeRentals: 0,
    expiredRentals: 0,
    pendingRentals: 0,
    totalMonthlyRevenue: 0,
    paidThisMonth: 0,
    pendingThisMonth: 0,
    overduePayments: 0,
    occupancyRate: 0,
    averageRentalValue: 0,
    expiringContracts: 0,
    recentRentals: [],
    paymentsByStatus: [],
    monthlyRevenueChart: [],
  );

  factory RentalDashboardData.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return <T>[];
      return raw.map(_asMap).whereType<Map<String, dynamic>>().map(f).toList();
    }

    return RentalDashboardData(
      totalRentals: _toInt(json['totalRentals']),
      activeRentals: _toInt(json['activeRentals']),
      expiredRentals: _toInt(json['expiredRentals']),
      pendingRentals: _toInt(json['pendingRentals']),
      totalMonthlyRevenue: _toDouble(json['totalMonthlyRevenue']),
      paidThisMonth: _toDouble(json['paidThisMonth']),
      pendingThisMonth: _toDouble(json['pendingThisMonth']),
      overduePayments: _toInt(json['overduePayments']),
      occupancyRate: _toDouble(json['occupancyRate']),
      averageRentalValue: _toDouble(json['averageRentalValue']),
      expiringContracts: _toInt(json['expiringContracts']),
      recentRentals: listOf(json['recentRentals'], RentalDashboardRecent.fromJson),
      paymentsByStatus:
          listOf(json['paymentsByStatus'], RentalPaymentsByStatus.fromJson),
      monthlyRevenueChart: listOf(
          json['monthlyRevenueChart'], RentalMonthlyRevenuePoint.fromJson),
    );
  }
}

// ─── Payload de criação/edição ───────────────────────────────────────────────

/// Espelha `CreateRentalRequest` / `UpdateRentalRequest` do web. Apenas os
/// campos não nulos entram no JSON.
class RentalPayload {
  final String tenantName;
  final String tenantDocument;
  final String? tenantPhone;
  final String? tenantEmail;

  /// `yyyy-MM-dd`
  final String startDate;

  /// `yyyy-MM-dd`
  final String endDate;
  final double monthlyValue;
  final int dueDay;
  final String propertyId;
  final String? observations;
  final double? depositValue;
  final bool autoGeneratePayments;
  final bool sendBilletByEmail;
  final double? lateFeePercent;
  final double? interestPerMonthPercent;

  const RentalPayload({
    required this.tenantName,
    required this.tenantDocument,
    this.tenantPhone,
    this.tenantEmail,
    required this.startDate,
    required this.endDate,
    required this.monthlyValue,
    required this.dueDay,
    required this.propertyId,
    this.observations,
    this.depositValue,
    this.autoGeneratePayments = true,
    this.sendBilletByEmail = false,
    this.lateFeePercent,
    this.interestPerMonthPercent,
  });

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'tenantName': tenantName,
      'tenantDocument': tenantDocument,
      'startDate': startDate,
      'endDate': endDate,
      'monthlyValue': monthlyValue,
      'dueDay': dueDay,
      'propertyId': propertyId,
      'autoGeneratePayments': autoGeneratePayments,
      'sendBilletByEmail': sendBilletByEmail,
    };
    if ((tenantPhone ?? '').trim().isNotEmpty) {
      out['tenantPhone'] = tenantPhone!.trim();
    }
    if ((tenantEmail ?? '').trim().isNotEmpty) {
      out['tenantEmail'] = tenantEmail!.trim();
    }
    if ((observations ?? '').trim().isNotEmpty) {
      out['observations'] = observations!.trim();
    }
    if (depositValue != null && depositValue! > 0) {
      out['depositValue'] = depositValue;
    }
    if (lateFeePercent != null) out['lateFeePercent'] = lateFeePercent;
    if (interestPerMonthPercent != null) {
      out['interestPerMonthPercent'] = interestPerMonthPercent;
    }
    return out;
  }
}
