// Modelos do módulo Relatórios de Visita — espelham o contrato do backend
// (`VisitReportController` em `/visit-reports`) e os tipos do imobx-front
// (`src/types/visitReport.ts`). Parse defensivo: campos podem vir null,
// string ou number.

/// Status da assinatura do relatório (1:1 com `VisitReportSignatureStatus`).
enum VisitSignatureStatus {
  pending,
  signed,
  expired,
  unknown;

  static VisitSignatureStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return VisitSignatureStatus.pending;
      case 'signed':
        return VisitSignatureStatus.signed;
      case 'expired':
        return VisitSignatureStatus.expired;
      default:
        return VisitSignatureStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case VisitSignatureStatus.pending:
        return 'Aguardando assinatura';
      case VisitSignatureStatus.signed:
        return 'Assinado';
      case VisitSignatureStatus.expired:
        return 'Expirado';
      case VisitSignatureStatus.unknown:
        return 'Visita';
    }
  }

  /// Rótulo curto para chips/coluna estreita.
  String get shortLabel {
    switch (this) {
      case VisitSignatureStatus.pending:
        return 'Aguardando';
      case VisitSignatureStatus.signed:
        return 'Assinado';
      case VisitSignatureStatus.expired:
        return 'Expirado';
      case VisitSignatureStatus.unknown:
        return 'Visita';
    }
  }

  /// Valor enviado/comparado com o backend.
  String get raw => name;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// `visitDate` chega como data pura (`YYYY-MM-DD`). Parse ao meio-dia local
/// para não deslocar o dia por fuso (mesmo truque do web: `d + 'T12:00:00'`).
DateTime? _toDateOnly(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final ymd = s.length >= 10 ? s.substring(0, 10) : s;
  return DateTime.tryParse('${ymd}T12:00:00');
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

String? _toTrimmedOrNull(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Imóvel visitado dentro do relatório.
class VisitReportProperty {
  final String id;
  final String? propertyId;
  final String? propertyCode;
  final String address;
  final String? reference;
  final int displayOrder;

  const VisitReportProperty({
    required this.id,
    this.propertyId,
    this.propertyCode,
    required this.address,
    this.reference,
    required this.displayOrder,
  });

  factory VisitReportProperty.fromJson(Map<String, dynamic> json) {
    return VisitReportProperty(
      id: json['id']?.toString() ?? '',
      propertyId: _toTrimmedOrNull(json['propertyId'] ?? json['property_id']),
      propertyCode:
          _toTrimmedOrNull(json['propertyCode'] ?? json['property_code']),
      address: json['address']?.toString().trim() ?? '',
      reference: _toTrimmedOrNull(json['reference']),
      displayOrder: _toInt(json['displayOrder'] ?? json['display_order']),
    );
  }

  /// Payload de criação/atualização (`CreateVisitReportPropertyDto`).
  Map<String, dynamic> toDto(int order) => {
        if (propertyId != null && propertyId!.isNotEmpty)
          'propertyId': propertyId,
        'address': address.trim(),
        if (reference != null && reference!.isNotEmpty)
          'reference': reference!.trim(),
        'displayOrder': order,
      };
}

/// Relatório de visita (`VisitReportResponseDto`).
class VisitReport {
  final String id;
  final String clientId;
  final String? clientName;
  final String? createdById;
  final String? createdByName;
  final DateTime? visitDate;
  final String? kanbanTaskId;
  final String? kanbanTaskTitle;
  final VisitSignatureStatus signatureStatus;
  final DateTime? signatureExpiresAt;
  final DateTime? signedAt;
  final String? signerName;
  final String? notes;
  final List<VisitReportProperty> properties;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VisitReport({
    required this.id,
    required this.clientId,
    this.clientName,
    this.createdById,
    this.createdByName,
    this.visitDate,
    this.kanbanTaskId,
    this.kanbanTaskTitle,
    required this.signatureStatus,
    this.signatureExpiresAt,
    this.signedAt,
    this.signerName,
    this.notes,
    required this.properties,
    this.createdAt,
    this.updatedAt,
  });

  /// Link de assinatura ativo (pendente e ainda não expirado) — mesma regra
  /// do web (`hasActiveLink` em `VisitReportListPage`).
  bool get hasActiveLink =>
      signatureStatus == VisitSignatureStatus.pending &&
      signatureExpiresAt != null &&
      signatureExpiresAt!.isAfter(DateTime.now());

  bool get isSigned => signatureStatus == VisitSignatureStatus.signed;

  /// Melhor rótulo do cliente para exibir.
  String get clientLabel {
    final n = (clientName ?? '').trim();
    return n.isNotEmpty ? n : 'Cliente';
  }

  /// Endereço do primeiro imóvel (ordenado por `displayOrder`).
  String? get firstAddress {
    if (properties.isEmpty) return null;
    final sorted = [...properties]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final addr = sorted.first.address.trim();
    return addr.isEmpty ? null : addr;
  }

  factory VisitReport.fromJson(Map<String, dynamic> json) {
    final rawProps = json['properties'];
    final props = rawProps is List
        ? rawProps
            .whereType<Map>()
            .map((e) =>
                VisitReportProperty.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <VisitReportProperty>[];
    props.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return VisitReport(
      id: json['id']?.toString() ?? '',
      clientId: json['clientId']?.toString() ?? '',
      clientName: _toTrimmedOrNull(json['clientName'] ?? json['client_name']),
      createdById:
          _toTrimmedOrNull(json['createdById'] ?? json['created_by_id']),
      createdByName:
          _toTrimmedOrNull(json['createdByName'] ?? json['created_by_name']),
      visitDate: _toDateOnly(json['visitDate'] ?? json['visit_date']),
      kanbanTaskId:
          _toTrimmedOrNull(json['kanbanTaskId'] ?? json['kanban_task_id']),
      kanbanTaskTitle: _toTrimmedOrNull(
          json['kanbanTaskTitle'] ?? json['kanban_task_title']),
      signatureStatus: VisitSignatureStatus.fromRaw(
          (json['signatureStatus'] ?? json['signature_status'])?.toString()),
      signatureExpiresAt:
          _toDate(json['signatureExpiresAt'] ?? json['signature_expires_at']),
      signedAt: _toDate(json['signedAt'] ?? json['signed_at']),
      signerName: _toTrimmedOrNull(json['signerName'] ?? json['signer_name']),
      notes: _toTrimmedOrNull(json['notes']),
      properties: props,
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Resposta de `POST /visit-reports/:id/generate-signature-link` e de
/// `GET /visit-reports/:id/signature-link`.
class VisitSignatureLink {
  final String url;
  final DateTime? expiresAt;

  const VisitSignatureLink({required this.url, this.expiresAt});

  factory VisitSignatureLink.fromJson(Map<String, dynamic> json) {
    return VisitSignatureLink(
      url: (json['signatureUrl'] ?? json['url'])?.toString() ?? '',
      expiresAt: _toDate(json['expiresAt'] ?? json['expires_at']),
    );
  }
}

/// Filtros da lista (`GET /visit-reports`). `status` é refinado no cliente —
/// paridade com o web, que também filtra o status em memória.
class VisitReportFilters {
  final String? clientId;

  /// Nome exibido do cliente filtrado (apenas UI — não vai na query).
  final String? clientLabel;
  final DateTime? fromDate;
  final DateTime? toDate;
  final VisitSignatureStatus? status;

  const VisitReportFilters({
    this.clientId,
    this.clientLabel,
    this.fromDate,
    this.toDate,
    this.status,
  });

  static const empty = VisitReportFilters();

  int get activeCount =>
      (clientId != null ? 1 : 0) +
      (fromDate != null ? 1 : 0) +
      (toDate != null ? 1 : 0) +
      (status != null ? 1 : 0);

  bool get hasBackendFilters =>
      clientId != null || fromDate != null || toDate != null;

  VisitReportFilters copyWith({
    String? clientId,
    String? clientLabel,
    DateTime? fromDate,
    DateTime? toDate,
    VisitSignatureStatus? status,
    bool resetClient = false,
    bool resetFromDate = false,
    bool resetToDate = false,
    bool resetStatus = false,
  }) {
    return VisitReportFilters(
      clientId: resetClient ? null : (clientId ?? this.clientId),
      clientLabel: resetClient ? null : (clientLabel ?? this.clientLabel),
      fromDate: resetFromDate ? null : (fromDate ?? this.fromDate),
      toDate: resetToDate ? null : (toDate ?? this.toDate),
      status: resetStatus ? null : (status ?? this.status),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Query string para o backend. `scope=all` exige `visit:manage` (ou
  /// `kanban:view`) — ver guard no `VisitReportController`.
  Map<String, String> toQueryParams({required bool scopeAll}) {
    final out = <String, String>{'scope': scopeAll ? 'all' : 'mine'};
    if (clientId != null && clientId!.isNotEmpty) out['clientId'] = clientId!;
    if (fromDate != null) out['fromDate'] = _ymd(fromDate!);
    if (toDate != null) out['toDate'] = _ymd(toDate!);
    return out;
  }
}

/// Opção do seletor de clientes (busca em `GET /clients?search=`).
class ClientPickOption {
  final String id;
  final String name;
  final String? cpf;
  final String? phone;

  const ClientPickOption({
    required this.id,
    required this.name,
    this.cpf,
    this.phone,
  });

  factory ClientPickOption.fromJson(Map<String, dynamic> json) {
    return ClientPickOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString().trim() ?? '',
      cpf: _toTrimmedOrNull(json['cpf']),
      phone: _toTrimmedOrNull(
          json['phone'] ?? json['cellphone'] ?? json['phoneNumber']),
    );
  }
}

/// Opção do seletor de imóveis (busca em `GET /properties?search=`).
class PropertyPickOption {
  final String id;
  final String title;
  final String? code;
  final String address;

  const PropertyPickOption({
    required this.id,
    required this.title,
    this.code,
    required this.address,
  });

  factory PropertyPickOption.fromJson(Map<String, dynamic> json) {
    String address = '';
    final rawAddr = json['address'];
    if (rawAddr is String) {
      address = rawAddr.trim();
    } else if (rawAddr is Map) {
      final a = Map<String, dynamic>.from(rawAddr);
      final parts = <String>[
        a['street']?.toString().trim() ?? '',
        a['number']?.toString().trim() ?? '',
        a['neighborhood']?.toString().trim() ?? '',
        a['city']?.toString().trim() ?? '',
      ].where((p) => p.isNotEmpty).toList();
      address = parts.join(', ');
    }
    return PropertyPickOption(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString().trim() ?? '',
      code: _toTrimmedOrNull(json['code']),
      address: address,
    );
  }

  /// Rótulo compacto — "Ref. CÓD — endereço" quando houver código.
  String get displayLabel {
    final t = title.isNotEmpty ? title : address;
    if (code != null && code!.isNotEmpty) return '$code · $t';
    return t;
  }
}
