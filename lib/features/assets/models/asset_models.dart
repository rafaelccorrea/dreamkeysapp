// Modelos do módulo de Patrimônio — espelham `asset.entity.ts` /
// `asset-response.dto.ts` do backend e `asset.ts` do imobx-front.

/// Categoria do patrimônio (1:1 com `AssetCategory` do backend).
enum AssetCategory {
  electronics,
  furniture,
  vehicle,
  officeSupplies,
  buildingEquipment,
  other;

  static AssetCategory fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'electronics':
        return AssetCategory.electronics;
      case 'furniture':
        return AssetCategory.furniture;
      case 'vehicle':
        return AssetCategory.vehicle;
      case 'office_supplies':
        return AssetCategory.officeSupplies;
      case 'building_equipment':
        return AssetCategory.buildingEquipment;
      default:
        return AssetCategory.other;
    }
  }

  String get label {
    switch (this) {
      case AssetCategory.electronics:
        return 'Eletrônicos';
      case AssetCategory.furniture:
        return 'Mobiliário';
      case AssetCategory.vehicle:
        return 'Veículos';
      case AssetCategory.officeSupplies:
        return 'Escritório';
      case AssetCategory.buildingEquipment:
        return 'Equip. prediais';
      case AssetCategory.other:
        return 'Outros';
    }
  }

  String get apiValue {
    switch (this) {
      case AssetCategory.electronics:
        return 'electronics';
      case AssetCategory.furniture:
        return 'furniture';
      case AssetCategory.vehicle:
        return 'vehicle';
      case AssetCategory.officeSupplies:
        return 'office_supplies';
      case AssetCategory.buildingEquipment:
        return 'building_equipment';
      case AssetCategory.other:
        return 'other';
    }
  }
}

/// Status do patrimônio (1:1 com `AssetStatus` do backend).
enum AssetStatus {
  available,
  inUse,
  maintenance,
  disposed,
  lost,
  unknown;

  static AssetStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'available':
        return AssetStatus.available;
      case 'in_use':
        return AssetStatus.inUse;
      case 'maintenance':
        return AssetStatus.maintenance;
      case 'disposed':
        return AssetStatus.disposed;
      case 'lost':
        return AssetStatus.lost;
      default:
        return AssetStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case AssetStatus.available:
        return 'Disponível';
      case AssetStatus.inUse:
        return 'Em uso';
      case AssetStatus.maintenance:
        return 'Manutenção';
      case AssetStatus.disposed:
        return 'Baixado';
      case AssetStatus.lost:
        return 'Perdido';
      case AssetStatus.unknown:
        return 'Patrimônio';
    }
  }

  String get apiValue {
    switch (this) {
      case AssetStatus.available:
        return 'available';
      case AssetStatus.inUse:
        return 'in_use';
      case AssetStatus.maintenance:
        return 'maintenance';
      case AssetStatus.disposed:
        return 'disposed';
      case AssetStatus.lost:
        return 'lost';
      case AssetStatus.unknown:
        return 'available';
    }
  }

  /// Ativo no acervo (não baixado nem perdido).
  bool get isActive =>
      this == AssetStatus.available ||
      this == AssetStatus.inUse ||
      this == AssetStatus.maintenance;
}

/// Tipo de movimentação (1:1 com `MovementType` do backend).
enum AssetMovementType {
  entry,
  exit,
  transfer,
  statusChange,
  maintenance,
  unknown;

  static AssetMovementType fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'entry':
        return AssetMovementType.entry;
      case 'exit':
        return AssetMovementType.exit;
      case 'transfer':
        return AssetMovementType.transfer;
      case 'status_change':
        return AssetMovementType.statusChange;
      case 'maintenance':
        return AssetMovementType.maintenance;
      default:
        return AssetMovementType.unknown;
    }
  }

  String get label {
    switch (this) {
      case AssetMovementType.entry:
        return 'Entrada/Aquisição';
      case AssetMovementType.exit:
        return 'Saída/Baixa';
      case AssetMovementType.transfer:
        return 'Transferência';
      case AssetMovementType.statusChange:
        return 'Mudança de status';
      case AssetMovementType.maintenance:
        return 'Manutenção';
      case AssetMovementType.unknown:
        return 'Movimentação';
    }
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
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

/// Patrimônio — `GET /assets` e `GET /assets/:id`.
class Asset {
  final String id;
  final String name;
  final String? description;
  final AssetCategory category;
  final AssetStatus status;
  final double value;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final DateTime? acquisitionDate;
  final String? location;
  final String? notes;
  final DateTime? createdAt;

  // Relations desnormalizadas.
  final String? assignedToUserId;
  final String? assignedToUserName;
  final String? propertyId;
  final String? propertyTitle;
  final String? propertyCode;
  final String? createdByName;

  const Asset({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    required this.status,
    required this.value,
    this.serialNumber,
    this.brand,
    this.model,
    this.acquisitionDate,
    this.location,
    this.notes,
    this.createdAt,
    this.assignedToUserId,
    this.assignedToUserName,
    this.propertyId,
    this.propertyTitle,
    this.propertyCode,
    this.createdByName,
  });

  /// Rótulo composto "marca · modelo" (o que existir).
  String? get brandModelLabel {
    final b = (brand ?? '').trim();
    final m = (model ?? '').trim();
    if (b.isEmpty && m.isEmpty) return null;
    if (b.isEmpty) return m;
    if (m.isEmpty) return b;
    return '$b · $m';
  }

  factory Asset.fromJson(Map<String, dynamic> json) {
    final assigned = _asMap(json['assignedToUser']);
    final property = _asMap(json['property']);
    final createdBy = _asMap(json['createdBy']);
    return Asset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      category: AssetCategory.fromRaw(json['category']?.toString()),
      status: AssetStatus.fromRaw(json['status']?.toString()),
      value: _toDouble(json['value']),
      serialNumber:
          (json['serialNumber'] ?? json['serial_number'])?.toString(),
      brand: json['brand']?.toString(),
      model: json['model']?.toString(),
      acquisitionDate:
          _toDate(json['acquisitionDate'] ?? json['acquisition_date']),
      location: json['location']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      assignedToUserId: assigned?['id']?.toString() ??
          (json['assignedToUserId'] ?? json['assigned_to_user_id'])
              ?.toString(),
      assignedToUserName: assigned?['name']?.toString(),
      propertyId: property?['id']?.toString() ??
          (json['propertyId'] ?? json['property_id'])?.toString(),
      propertyTitle: property?['title']?.toString(),
      propertyCode: property?['code']?.toString(),
      createdByName: createdBy?['name']?.toString(),
    );
  }
}

/// Movimentação de patrimônio — `GET /assets/:id/movements`.
class AssetMovement {
  final String id;
  final AssetMovementType type;
  final DateTime? movementDate;
  final String reason;
  final String? fromUserName;
  final String? toUserName;
  final String? fromPropertyTitle;
  final String? toPropertyTitle;
  final AssetStatus? previousStatus;
  final AssetStatus? newStatus;
  final String? notes;
  final String? recordedByName;
  final DateTime? createdAt;

  const AssetMovement({
    required this.id,
    required this.type,
    this.movementDate,
    required this.reason,
    this.fromUserName,
    this.toUserName,
    this.fromPropertyTitle,
    this.toPropertyTitle,
    this.previousStatus,
    this.newStatus,
    this.notes,
    this.recordedByName,
    this.createdAt,
  });

  factory AssetMovement.fromJson(Map<String, dynamic> json) {
    final fromUser = _asMap(json['fromUser']);
    final toUser = _asMap(json['toUser']);
    final fromProperty = _asMap(json['fromProperty']);
    final toProperty = _asMap(json['toProperty']);
    final recordedBy = _asMap(json['recordedBy']);
    final prev = (json['previousStatus'] ?? json['previous_status'])
        ?.toString();
    final next = (json['newStatus'] ?? json['new_status'])?.toString();
    return AssetMovement(
      id: json['id']?.toString() ?? '',
      type: AssetMovementType.fromRaw(json['type']?.toString()),
      movementDate:
          _toDate(json['movementDate'] ?? json['movement_date']),
      reason: json['reason']?.toString() ?? '',
      fromUserName: fromUser?['name']?.toString(),
      toUserName: toUser?['name']?.toString(),
      fromPropertyTitle: fromProperty?['title']?.toString(),
      toPropertyTitle: toProperty?['title']?.toString(),
      previousStatus:
          prev == null || prev.isEmpty ? null : AssetStatus.fromRaw(prev),
      newStatus:
          next == null || next.isEmpty ? null : AssetStatus.fromRaw(next),
      notes: json['notes']?.toString(),
      recordedByName: recordedBy?['name']?.toString(),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
    );
  }
}

/// Estatísticas — `GET /assets/stats`.
class AssetStats {
  final int total;
  final double totalValue;
  final Map<String, int> byStatus;
  final Map<String, int> byCategory;

  const AssetStats({
    required this.total,
    required this.totalValue,
    required this.byStatus,
    required this.byCategory,
  });

  static const zero = AssetStats(
    total: 0,
    totalValue: 0,
    byStatus: {},
    byCategory: {},
  );

  int countFor(AssetStatus status) => byStatus[status.apiValue] ?? 0;

  factory AssetStats.fromJson(Map<String, dynamic> json) {
    Map<String, int> toCountMap(dynamic v) {
      final m = _asMap(v);
      if (m == null) return const {};
      return m.map((k, val) => MapEntry(k, _toInt(val)));
    }

    return AssetStats(
      total: _toInt(json['total']),
      totalValue: _toDouble(json['totalValue']),
      byStatus: toCountMap(json['byStatus']),
      byCategory: toCountMap(json['byCategory']),
    );
  }
}

/// Resposta paginada de `GET /assets` (`{ assets, total }`).
class AssetListResult {
  final List<Asset> assets;
  final int total;

  const AssetListResult({required this.assets, required this.total});

  static const empty = AssetListResult(assets: [], total: 0);

  factory AssetListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['assets'] ?? json['data'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Asset.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Asset>[];
    return AssetListResult(
      assets: list,
      total: _toInt(json['total'], list.length),
    );
  }
}

/// Filtros de `GET /assets` (todos viram query string).
class AssetFilters {
  final AssetStatus? status;
  final AssetCategory? category;
  final String? assignedToUserId;
  final String? propertyId;
  final String? search;
  final bool onlyMyData;
  final int page;
  final int limit;

  const AssetFilters({
    this.status,
    this.category,
    this.assignedToUserId,
    this.propertyId,
    this.search,
    this.onlyMyData = false,
    this.page = 1,
    this.limit = 20,
  });

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (status != null && status != AssetStatus.unknown) {
      out['status'] = status!.apiValue;
    }
    if (category != null) out['category'] = category!.apiValue;
    if (assignedToUserId != null && assignedToUserId!.isNotEmpty) {
      out['assignedToUserId'] = assignedToUserId!;
    }
    if (propertyId != null && propertyId!.isNotEmpty) {
      out['propertyId'] = propertyId!;
    }
    final s = search?.trim();
    if (s != null && s.isNotEmpty) out['search'] = s;
    if (onlyMyData) out['onlyMyData'] = 'true';
    return out;
  }
}

/// Payload de criação/edição (`POST /assets` / `PATCH /assets/:id`).
class AssetDraft {
  final String name;
  final String? description;
  final AssetCategory category;
  final AssetStatus? status;
  final double value;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final String? acquisitionDate; // yyyy-MM-dd
  final String? location;
  final String? notes;
  final String? assignedToUserId;
  final String? propertyId;

  const AssetDraft({
    required this.name,
    this.description,
    required this.category,
    this.status,
    required this.value,
    this.serialNumber,
    this.brand,
    this.model,
    this.acquisitionDate,
    this.location,
    this.notes,
    this.assignedToUserId,
    this.propertyId,
  });

  Map<String, dynamic> toJson() {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return {
      'name': name.trim(),
      if (clean(description) != null) 'description': clean(description),
      'category': category.apiValue,
      if (status != null && status != AssetStatus.unknown)
        'status': status!.apiValue,
      'value': value,
      if (clean(serialNumber) != null) 'serialNumber': clean(serialNumber),
      if (clean(brand) != null) 'brand': clean(brand),
      if (clean(model) != null) 'model': clean(model),
      if (clean(acquisitionDate) != null)
        'acquisitionDate': clean(acquisitionDate),
      if (clean(location) != null) 'location': clean(location),
      if (clean(notes) != null) 'notes': clean(notes),
      if (clean(assignedToUserId) != null)
        'assignedToUserId': clean(assignedToUserId),
      if (clean(propertyId) != null) 'propertyId': clean(propertyId),
    };
  }
}
