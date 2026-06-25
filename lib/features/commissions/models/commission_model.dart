// Modelos do módulo de Comissões — espelham `commission.entity.ts` e a
// resposta de `GET /commissions` + `GET /commissions/statistics` do backend.

/// Status da comissão (1:1 com `CommissionStatus` do backend).
enum CommissionStatus {
  pending,
  approved,
  paid,
  cancelled,
  unknown;

  static CommissionStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return CommissionStatus.pending;
      case 'approved':
        return CommissionStatus.approved;
      case 'paid':
        return CommissionStatus.paid;
      case 'cancelled':
      case 'canceled':
        return CommissionStatus.cancelled;
      default:
        return CommissionStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case CommissionStatus.pending:
        return 'Pendente';
      case CommissionStatus.approved:
        return 'Aprovada';
      case CommissionStatus.paid:
        return 'Recebida';
      case CommissionStatus.cancelled:
        return 'Cancelada';
      case CommissionStatus.unknown:
        return 'Comissão';
    }
  }

  /// Pendente "no bolso": ainda não paga e não cancelada (pending OU approved).
  bool get isOpen =>
      this == CommissionStatus.pending || this == CommissionStatus.approved;
}

/// Tipo da transação que gerou a comissão.
enum CommissionType {
  sale,
  rental,
  management,
  unknown;

  static CommissionType fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'sale':
        return CommissionType.sale;
      case 'rental':
        return CommissionType.rental;
      case 'management':
        return CommissionType.management;
      default:
        return CommissionType.unknown;
    }
  }

  String get label {
    switch (this) {
      case CommissionType.sale:
        return 'Venda';
      case CommissionType.rental:
        return 'Aluguel';
      case CommissionType.management:
        return 'Administração';
      case CommissionType.unknown:
        return 'Outro';
    }
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

class Commission {
  final String id;
  final String title;
  final CommissionType type;
  final CommissionStatus status;
  final double baseValue;
  final double percentage;
  final double commissionValue;
  final double taxValue;
  final double netValue;
  final String? notes;
  final DateTime? expectedPaymentDate;
  final DateTime? paidAt;
  final DateTime? createdAt;

  // Dados desnormalizados (vêm das relations do backend).
  final String? clientName;
  final String? propertyTitle;
  final String? propertyAddress;
  final String? propertyCode;
  final String? userName;

  const Commission({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.baseValue,
    required this.percentage,
    required this.commissionValue,
    required this.taxValue,
    required this.netValue,
    this.notes,
    this.expectedPaymentDate,
    this.paidAt,
    this.createdAt,
    this.clientName,
    this.propertyTitle,
    this.propertyAddress,
    this.propertyCode,
    this.userName,
  });

  bool get isPaid => status == CommissionStatus.paid;
  bool get isOpen => status.isOpen;

  /// Melhor rótulo descritivo do imóvel para exibir no card.
  String? get propertyLabel {
    final title = (propertyTitle ?? '').trim();
    if (title.isNotEmpty) return title;
    final addr = (propertyAddress ?? '').trim();
    if (addr.isNotEmpty) return addr;
    return null;
  }

  factory Commission.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      return v is Map<String, dynamic> ? v : null;
    }

    final property = nested('property');
    final client = nested('client');
    final user = nested('user');

    return Commission(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: CommissionType.fromRaw(json['type']?.toString()),
      status: CommissionStatus.fromRaw(json['status']?.toString()),
      baseValue: _toDouble(json['baseValue'] ?? json['base_value']),
      percentage: _toDouble(json['percentage']),
      commissionValue:
          _toDouble(json['commissionValue'] ?? json['commission_value']),
      taxValue: _toDouble(json['taxValue'] ?? json['tax_value']),
      netValue: _toDouble(json['netValue'] ?? json['net_value']),
      notes: json['notes']?.toString(),
      expectedPaymentDate: _toDate(
          json['expectedPaymentDate'] ?? json['expected_payment_date']),
      paidAt: _toDate(json['paidAt'] ?? json['paid_at']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      clientName: client?['name']?.toString(),
      propertyTitle: property?['title']?.toString(),
      propertyAddress: property?['address']?.toString(),
      propertyCode: property?['code']?.toString(),
      userName: user?['name']?.toString(),
    );
  }
}

/// Resposta paginada de `GET /commissions`.
class CommissionListResult {
  final List<Commission> commissions;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const CommissionListResult({
    required this.commissions,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const empty = CommissionListResult(
    commissions: [],
    total: 0,
    page: 1,
    limit: 50,
    totalPages: 1,
  );

  factory CommissionListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['commissions'] ?? json['data'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Commission.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Commission>[];
    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return CommissionListResult(
      commissions: list,
      total: asInt(json['total'], list.length),
      page: asInt(json['page'], 1),
      limit: asInt(json['limit'], 50),
      totalPages: asInt(json['totalPages'], 1),
    );
  }
}

/// Resposta de `GET /commissions/statistics`.
class CommissionStats {
  final int total;
  final int pending;
  final int approved;
  final int paid;
  final double totalValue;
  final double totalNet;
  final double totalPaid;
  final double totalPending;
  final double thisMonthValue;

  const CommissionStats({
    required this.total,
    required this.pending,
    required this.approved,
    required this.paid,
    required this.totalValue,
    required this.totalNet,
    required this.totalPaid,
    required this.totalPending,
    required this.thisMonthValue,
  });

  static const zero = CommissionStats(
    total: 0,
    pending: 0,
    approved: 0,
    paid: 0,
    totalValue: 0,
    totalNet: 0,
    totalPaid: 0,
    totalPending: 0,
    thisMonthValue: 0,
  );

  /// Quantidade "em aberto" (pendentes + aprovadas).
  int get openCount => pending + approved;

  factory CommissionStats.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return CommissionStats(
      total: asInt(json['total']),
      pending: asInt(json['pending']),
      approved: asInt(json['approved']),
      paid: asInt(json['paid']),
      totalValue: _toDouble(json['totalValue']),
      totalNet: _toDouble(json['totalNet']),
      totalPaid: _toDouble(json['totalPaid']),
      totalPending: _toDouble(json['totalPending']),
      thisMonthValue: _toDouble(json['thisMonthValue']),
    );
  }
}

/// Aba ativa da tela de comissões — define o filtro enviado ao backend.
enum CommissionTab { pending, received, history }

/// Filtros de `GET /commissions` (todos viram query string).
class CommissionFilters {
  final CommissionStatus? status;
  final bool? paid;
  final String? search;
  final int page;
  final int limit;

  const CommissionFilters({
    this.status,
    this.paid,
    this.search,
    this.page = 1,
    this.limit = 50,
  });

  CommissionFilters copyWith({
    CommissionStatus? status,
    bool? paid,
    String? search,
    int? page,
    int? limit,
  }) {
    return CommissionFilters(
      status: status ?? this.status,
      paid: paid ?? this.paid,
      search: search ?? this.search,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (paid != null) out['paid'] = paid! ? 'true' : 'false';
    if (status != null && status != CommissionStatus.unknown) {
      out['status'] = status!.name;
    }
    final s = search?.trim();
    if (s != null && s.isNotEmpty) out['search'] = s;
    return out;
  }
}
