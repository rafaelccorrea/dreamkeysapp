// Modelos do módulo de Checklists standalone — espelham
// `sale-checklist-response.dto.ts` do backend e `checklist.types.ts` do web.

/// Tipo do checklist (venda ou aluguel) — 1:1 com o backend.
enum ChecklistType {
  sale,
  rental,
  unknown;

  static ChecklistType fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'sale':
        return ChecklistType.sale;
      case 'rental':
        return ChecklistType.rental;
      default:
        return ChecklistType.unknown;
    }
  }

  String get label {
    switch (this) {
      case ChecklistType.sale:
        return 'Venda';
      case ChecklistType.rental:
        return 'Aluguel';
      case ChecklistType.unknown:
        return 'Checklist';
    }
  }

  /// Valor exato enviado ao backend.
  String get apiValue => this == ChecklistType.rental ? 'rental' : 'sale';
}

/// Status do checklist E dos itens (mesmo espaço de valores no backend).
enum ChecklistStatus {
  pending,
  inProgress,
  completed,
  skipped,
  unknown;

  static ChecklistStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return ChecklistStatus.pending;
      case 'in_progress':
        return ChecklistStatus.inProgress;
      case 'completed':
        return ChecklistStatus.completed;
      case 'skipped':
        return ChecklistStatus.skipped;
      default:
        return ChecklistStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case ChecklistStatus.pending:
        return 'Pendente';
      case ChecklistStatus.inProgress:
        return 'Em andamento';
      case ChecklistStatus.completed:
        return 'Concluído';
      case ChecklistStatus.skipped:
        return 'Pulado';
      case ChecklistStatus.unknown:
        return 'Checklist';
    }
  }

  /// Valor exato enviado ao backend (`pending|in_progress|completed|skipped`).
  String get apiValue {
    switch (this) {
      case ChecklistStatus.inProgress:
        return 'in_progress';
      case ChecklistStatus.completed:
        return 'completed';
      case ChecklistStatus.skipped:
        return 'skipped';
      case ChecklistStatus.pending:
      case ChecklistStatus.unknown:
        return 'pending';
    }
  }

  /// "Em aberto": ainda não concluído nem pulado.
  bool get isOpen =>
      this == ChecklistStatus.pending || this == ChecklistStatus.inProgress;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
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

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

List<String> _toStringList(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Item do checklist.
class ChecklistItem {
  final String id;
  final String title;
  final String? description;
  final ChecklistStatus status;
  final List<String> requiredDocuments;
  final int? estimatedDays;
  final int order;
  final DateTime? completedAt;
  final String? completedBy;
  final String? notes;

  const ChecklistItem({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    this.requiredDocuments = const [],
    this.estimatedDays,
    required this.order,
    this.completedAt,
    this.completedBy,
    this.notes,
  });

  bool get isCompleted => status == ChecklistStatus.completed;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final days = json['estimatedDays'] ?? json['estimated_days'];
    return ChecklistItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      status: ChecklistStatus.fromRaw(json['status']?.toString()),
      requiredDocuments: _toStringList(
          json['requiredDocuments'] ?? json['required_documents']),
      estimatedDays: days == null ? null : _toInt(days),
      order: _toInt(json['order'], 0),
      completedAt: _toDate(json['completedAt'] ?? json['completed_at']),
      completedBy:
          (json['completedBy'] ?? json['completed_by'])?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

/// Estatísticas agregadas de um checklist (vêm prontas do backend).
class ChecklistStatistics {
  final int totalItems;
  final int completedItems;
  final int pendingItems;
  final int inProgressItems;
  final double completionPercentage;

  const ChecklistStatistics({
    required this.totalItems,
    required this.completedItems,
    required this.pendingItems,
    required this.inProgressItems,
    required this.completionPercentage,
  });

  static const zero = ChecklistStatistics(
    totalItems: 0,
    completedItems: 0,
    pendingItems: 0,
    inProgressItems: 0,
    completionPercentage: 0,
  );

  factory ChecklistStatistics.fromJson(Map<String, dynamic> json) {
    return ChecklistStatistics(
      totalItems: _toInt(json['totalItems']),
      completedItems: _toInt(json['completedItems']),
      pendingItems: _toInt(json['pendingItems']),
      inProgressItems: _toInt(json['inProgressItems']),
      completionPercentage: _toDouble(json['completionPercentage']),
    );
  }
}

/// Checklist completo — `GET /sale-checklists` e `GET /sale-checklists/:id`.
class Checklist {
  final String id;
  final String propertyId;
  final String clientId;
  final ChecklistType type;
  final ChecklistStatus status;
  final List<ChecklistItem> items;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;
  final DateTime? createdAt;
  final ChecklistStatistics statistics;

  // Relations desnormalizadas.
  final String? propertyTitle;
  final String? propertyCode;
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? responsibleUserName;

  const Checklist({
    required this.id,
    required this.propertyId,
    required this.clientId,
    required this.type,
    required this.status,
    required this.items,
    this.startedAt,
    this.completedAt,
    this.notes,
    this.createdAt,
    required this.statistics,
    this.propertyTitle,
    this.propertyCode,
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.responsibleUserName,
  });

  bool get isOpen => status.isOpen;

  /// Estatísticas com fallback calculado dos itens (defensivo — o backend
  /// sempre manda, mas listas antigas podem vir sem).
  ChecklistStatistics get stats {
    if (statistics.totalItems > 0 || items.isEmpty) return statistics;
    final total = items.length;
    final done =
        items.where((i) => i.status == ChecklistStatus.completed).length;
    final progress =
        items.where((i) => i.status == ChecklistStatus.inProgress).length;
    final pending =
        items.where((i) => i.status == ChecklistStatus.pending).length;
    return ChecklistStatistics(
      totalItems: total,
      completedItems: done,
      pendingItems: pending,
      inProgressItems: progress,
      completionPercentage: total == 0 ? 0 : (done / total) * 100,
    );
  }

  factory Checklist.fromJson(Map<String, dynamic> json) {
    final property = _asMap(json['property']);
    final client = _asMap(json['client']);
    final responsible = _asMap(json['responsibleUser']);
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map(ChecklistItem.fromJson)
            .toList()
        : <ChecklistItem>[];
    items.sort((a, b) => a.order.compareTo(b.order));

    return Checklist(
      id: json['id']?.toString() ?? '',
      propertyId:
          (json['propertyId'] ?? json['property_id'])?.toString() ?? '',
      clientId: (json['clientId'] ?? json['client_id'])?.toString() ?? '',
      type: ChecklistType.fromRaw(json['type']?.toString()),
      status: ChecklistStatus.fromRaw(json['status']?.toString()),
      items: items,
      startedAt: _toDate(json['startedAt'] ?? json['started_at']),
      completedAt: _toDate(json['completedAt'] ?? json['completed_at']),
      notes: json['notes']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      statistics: _asMap(json['statistics']) != null
          ? ChecklistStatistics.fromJson(_asMap(json['statistics'])!)
          : ChecklistStatistics.zero,
      propertyTitle: property?['title']?.toString(),
      propertyCode: property?['code']?.toString(),
      clientName: client?['name']?.toString(),
      clientEmail: client?['email']?.toString(),
      clientPhone: client?['phone']?.toString(),
      responsibleUserName: responsible?['name']?.toString(),
    );
  }
}

/// Item enviado em create/update (`items[]` do DTO).
class ChecklistItemDraft {
  String title;
  String description;
  ChecklistStatus status;
  int? estimatedDays;
  int order;
  String notes;

  ChecklistItemDraft({
    this.title = '',
    this.description = '',
    this.status = ChecklistStatus.pending,
    this.estimatedDays,
    this.order = 1,
    this.notes = '',
  });

  factory ChecklistItemDraft.fromItem(ChecklistItem item) {
    return ChecklistItemDraft(
      title: item.title,
      description: item.description ?? '',
      status: item.status,
      estimatedDays: item.estimatedDays,
      order: item.order,
      notes: item.notes ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'status': status.apiValue,
      if (estimatedDays != null) 'estimatedDays': estimatedDays,
      'order': order,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
  }
}

/// Filtros de `GET /sale-checklists` — o backend NÃO pagina esta lista;
/// `search` é aplicado no cliente (paridade com o web).
class ChecklistFilters {
  final String? propertyId;
  final String? clientId;
  final ChecklistType? type;
  final ChecklistStatus? status;

  const ChecklistFilters({
    this.propertyId,
    this.clientId,
    this.type,
    this.status,
  });

  int get activeCount {
    var n = 0;
    if (type != null) n++;
    if (status != null) n++;
    if (propertyId != null) n++;
    if (clientId != null) n++;
    return n;
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{};
    if (propertyId != null && propertyId!.isNotEmpty) {
      out['propertyId'] = propertyId!;
    }
    if (clientId != null && clientId!.isNotEmpty) out['clientId'] = clientId!;
    if (type != null && type != ChecklistType.unknown) {
      out['type'] = type!.apiValue;
    }
    if (status != null && status != ChecklistStatus.unknown) {
      out['status'] = status!.apiValue;
    }
    return out;
  }
}

/// Template padrão de itens (paridade com `defaultTemplates` do web) —
/// exibido como prévia quando o usuário não personaliza itens.
class ChecklistDefaultTemplates {
  ChecklistDefaultTemplates._();

  static const sale = [
    (title: 'Documentação inicial', days: 3, description: 'Coleta de documentos básicos do cliente'),
    (title: 'Análise de crédito', days: 7, description: 'Avaliação da capacidade financeira do cliente'),
    (title: 'Vistoria técnica', days: 5, description: 'Inspeção completa da propriedade'),
    (title: 'Negociação e proposta', days: 5, description: 'Elaboração e apresentação da proposta comercial'),
    (title: 'Contrato de compra e venda', days: 10, description: 'Elaboração e assinatura do contrato'),
    (title: 'Financiamento', days: 15, description: 'Processamento e aprovação do financiamento'),
    (title: 'Escritura e registro', days: 10, description: 'Registro da escritura em cartório'),
    (title: 'Entrega das chaves', days: 1, description: 'Vistoria final e entrega das chaves'),
  ];

  static const rental = [
    (title: 'Documentação inicial', days: 3, description: 'Coleta de documentos básicos do locatário'),
    (title: 'Análise de perfil', days: 5, description: 'Avaliação do perfil do locatário'),
    (title: 'Vistoria de entrada', days: 2, description: 'Vistoria da propriedade antes da locação'),
    (title: 'Contrato de locação', days: 5, description: 'Elaboração e assinatura do contrato de locação'),
    (title: 'Pagamento e caução', days: 1, description: 'Recebimento do primeiro pagamento e caução'),
    (title: 'Entrega das chaves', days: 1, description: 'Vistoria final e entrega das chaves'),
  ];

  static List<({String title, int days, String description})> forType(
      ChecklistType type) {
    return type == ChecklistType.rental ? rental : sale;
  }
}
