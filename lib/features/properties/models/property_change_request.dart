import 'package:intl/intl.dart';

/// Situação de uma solicitação de alteração de campos protegidos.
/// Espelha `PropertyChangeRequestStatus` do backend
/// (`src/entities/property-change-request.entity.ts`).
enum PropertyChangeRequestStatus {
  pending('pending', 'Pendente'),
  approved('approved', 'Aprovada'),
  rejected('rejected', 'Recusada');

  final String value;
  final String label;
  const PropertyChangeRequestStatus(this.value, this.label);

  static PropertyChangeRequestStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'approved':
        return PropertyChangeRequestStatus.approved;
      case 'rejected':
        return PropertyChangeRequestStatus.rejected;
      default:
        return PropertyChangeRequestStatus.pending;
    }
  }
}

/// Referência mínima de usuário devolvida no `ChangeRequestView`.
class ChangeRequestUserRef {
  final String id;
  final String name;

  const ChangeRequestUserRef({required this.id, required this.name});

  static ChangeRequestUserRef? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString() ?? '';
    final name = map['name']?.toString() ?? '';
    if (id.isEmpty && name.isEmpty) return null;
    return ChangeRequestUserRef(id: id, name: name);
  }
}

/// Imóvel referenciado pela solicitação (pode ser `null` se foi removido).
class ChangeRequestPropertyRef {
  final String id;
  final String title;
  final String? code;

  const ChangeRequestPropertyRef({
    required this.id,
    required this.title,
    this.code,
  });

  static ChangeRequestPropertyRef? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return ChangeRequestPropertyRef(
      id: id,
      title: map['title']?.toString() ?? '',
      code: map['code']?.toString(),
    );
  }
}

/// Diff de um campo: valor antigo (snapshot), proposto e o vigente do imóvel.
class ChangeRequestFieldDiff {
  final String field;
  final String label;
  final dynamic oldValue;
  final dynamic newValue;
  final dynamic currentValue;

  /// `true` quando o valor atual do imóvel já difere do snapshot — conflito
  /// que o revisor precisa enxergar antes de aprovar.
  final bool changedSinceRequest;

  const ChangeRequestFieldDiff({
    required this.field,
    required this.label,
    required this.oldValue,
    required this.newValue,
    required this.currentValue,
    required this.changedSinceRequest,
  });

  factory ChangeRequestFieldDiff.fromJson(Map<String, dynamic> json) {
    return ChangeRequestFieldDiff(
      field: json['field']?.toString() ?? '',
      label: json['label']?.toString() ?? json['field']?.toString() ?? '',
      oldValue: json['old'],
      newValue: json['new'],
      currentValue: json['current'],
      changedSinceRequest: json['changedSinceRequest'] == true,
    );
  }

  /// Campos monetários — mesma lista do `MONEY_FIELDS` do web.
  static const Set<String> _moneyFields = {
    'salePrice',
    'rentPrice',
    'minSalePrice',
    'minRentPrice',
    'condominiumFee',
    'iptu',
  };

  /// Formatação idêntica ao `formatValue` do `PropertyChangeRequestsTab`:
  /// vazio vira travessão, lista de ids vira nomes, booleano vira Sim/Não e
  /// campo monetário sai em `NumberFormat` pt_BR.
  String format(dynamic value, Map<String, String> userNames) {
    if (value == null) return '—';
    if (value is String && value.trim().isEmpty) return '—';
    if (value is List) {
      if (value.isEmpty) return '—';
      return value
          .map((e) => userNames[e.toString()] ?? e.toString())
          .join(', ');
    }
    if (value is bool) return value ? 'Sim' : 'Não';
    if (_moneyFields.contains(field)) {
      final n = value is num ? value.toDouble() : double.tryParse('$value');
      if (n != null) {
        return NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
          decimalDigits: 2,
        ).format(n);
      }
    }
    return value.toString();
  }
}

/// Item de `GET /property-change-requests` (`ChangeRequestView` do backend).
class PropertyChangeRequest {
  final String id;
  final PropertyChangeRequestStatus status;
  final ChangeRequestPropertyRef? property;
  final ChangeRequestUserRef? requestedBy;
  final ChangeRequestUserRef? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ChangeRequestFieldDiff> changes;
  final Map<String, String> userNames;

  const PropertyChangeRequest({
    required this.id,
    required this.status,
    required this.property,
    required this.requestedBy,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    required this.changes,
    required this.userNames,
  });

  bool get isPending => status == PropertyChangeRequestStatus.pending;

  /// `true` quando ao menos um campo mudou desde a solicitação (conflito).
  bool get hasConflict => changes.any((c) => c.changedSinceRequest);

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory PropertyChangeRequest.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final changes = rawChanges is List
        ? rawChanges
            .whereType<Map>()
            .map((e) =>
                ChangeRequestFieldDiff.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ChangeRequestFieldDiff>[];

    final rawNames = json['userNames'];
    final userNames = <String, String>{};
    if (rawNames is Map) {
      rawNames.forEach((k, v) {
        userNames[k.toString()] = v?.toString() ?? '';
      });
    }

    return PropertyChangeRequest(
      id: json['id']?.toString() ?? '',
      status: PropertyChangeRequestStatus.fromString(json['status']?.toString()),
      property: ChangeRequestPropertyRef.fromJson(json['property']),
      requestedBy: ChangeRequestUserRef.fromJson(json['requestedBy']),
      reviewedBy: ChangeRequestUserRef.fromJson(json['reviewedBy']),
      reviewedAt: _parseDate(json['reviewedAt']),
      rejectionReason: json['rejectionReason']?.toString(),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      changes: changes,
      userNames: userNames,
    );
  }
}

/// Envelope de `GET /property-change-requests` — a lista já vem escopada pelo
/// backend e `canReview` diz se o usuário pode aprovar/recusar.
class PropertyChangeRequestList {
  final List<PropertyChangeRequest> items;
  final bool canReview;

  const PropertyChangeRequestList({
    required this.items,
    required this.canReview,
  });

  static const PropertyChangeRequestList empty =
      PropertyChangeRequestList(items: [], canReview: false);

  factory PropertyChangeRequestList.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PropertyChangeRequestList(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((e) =>
                  PropertyChangeRequest.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      canReview: json['canReview'] == true,
    );
  }
}

/// Entrada do histórico de envios da autorização do proprietário
/// (`GET /properties/:id/owner-authorization/send-history`).
class OwnerAuthSendEntry {
  final String id;
  final String? sentToEmail;
  final String? sentToName;
  final String? sentByUserName;
  final DateTime? createdAt;

  const OwnerAuthSendEntry({
    required this.id,
    this.sentToEmail,
    this.sentToName,
    this.sentByUserName,
    this.createdAt,
  });

  factory OwnerAuthSendEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['createdAt']?.toString();
    return OwnerAuthSendEntry(
      id: json['id']?.toString() ?? '',
      sentToEmail: json['sentToEmail']?.toString(),
      sentToName: json['sentToName']?.toString(),
      sentByUserName: json['sentByUserName']?.toString(),
      createdAt: raw == null || raw.isEmpty
          ? null
          : DateTime.tryParse(raw)?.toLocal(),
    );
  }
}

/// Resposta do histórico de envios — o backend responde tanto o envelope
/// `{ entries, signedAt, signedByName }` quanto um array puro (legado).
class OwnerAuthSendHistory {
  final List<OwnerAuthSendEntry> entries;
  final DateTime? signedAt;
  final String? signedByName;

  const OwnerAuthSendHistory({
    required this.entries,
    this.signedAt,
    this.signedByName,
  });

  static const OwnerAuthSendHistory empty = OwnerAuthSendHistory(entries: []);

  factory OwnerAuthSendHistory.fromAny(dynamic raw) {
    List<OwnerAuthSendEntry> parse(List<dynamic> list) => list
        .whereType<Map>()
        .map((e) => OwnerAuthSendEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    if (raw is List) {
      return OwnerAuthSendHistory(entries: parse(raw));
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final entries = map['entries'];
      final signedAtRaw = map['signedAt']?.toString();
      return OwnerAuthSendHistory(
        entries: entries is List ? parse(entries) : const [],
        signedAt: signedAtRaw == null || signedAtRaw.isEmpty
            ? null
            : DateTime.tryParse(signedAtRaw)?.toLocal(),
        signedByName: map['signedByName']?.toString(),
      );
    }
    return OwnerAuthSendHistory.empty;
  }
}

/// Status de votação de uma fila (`GET /properties/:id/voting-status`).
class ApprovalVotingStatus {
  final int approvedCount;
  final int rejectedCount;
  final int quorum;
  final int totalApprovers;
  final int pendingCount;
  final bool approversEnabled;

  const ApprovalVotingStatus({
    required this.approvedCount,
    required this.rejectedCount,
    required this.quorum,
    required this.totalApprovers,
    required this.pendingCount,
    required this.approversEnabled,
  });

  static const ApprovalVotingStatus empty = ApprovalVotingStatus(
    approvedCount: 0,
    rejectedCount: 0,
    quorum: 0,
    totalApprovers: 0,
    pendingCount: 0,
    approversEnabled: false,
  );

  factory ApprovalVotingStatus.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int lengthOf(dynamic v) => v is List ? v.length : 0;

    return ApprovalVotingStatus(
      approvedCount: asInt(json['approvedCount']),
      rejectedCount: asInt(json['rejectedCount']),
      quorum: asInt(json['quorum']),
      totalApprovers: lengthOf(json['approvers']),
      pendingCount: lengthOf(json['pendingApprovers']),
      approversEnabled: json['approversEnabled'] == true,
    );
  }
}
