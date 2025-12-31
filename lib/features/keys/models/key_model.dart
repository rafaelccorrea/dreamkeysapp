/// Tipos de chave
enum KeyType {
  main('main'),
  backup('backup'),
  emergency('emergency'),
  garage('garage'),
  mailbox('mailbox'),
  other('other');

  final String value;
  const KeyType(this.value);

  static KeyType fromString(String value) {
    return KeyType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KeyType.other,
    );
  }

  String get label {
    switch (this) {
      case KeyType.main:
        return 'Principal';
      case KeyType.backup:
        return 'Reserva';
      case KeyType.emergency:
        return 'Emergência';
      case KeyType.garage:
        return 'Garagem';
      case KeyType.mailbox:
        return 'Caixa de Correio';
      case KeyType.other:
        return 'Outro';
    }
  }
}

/// Status de chave
enum KeyStatus {
  available('available'),
  inUse('in_use'),
  lost('lost'),
  damaged('damaged'),
  maintenance('maintenance');

  final String value;
  const KeyStatus(this.value);

  static KeyStatus fromString(String value) {
    return KeyStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KeyStatus.available,
    );
  }

  String get label {
    switch (this) {
      case KeyStatus.available:
        return 'Disponível';
      case KeyStatus.inUse:
        return 'Em Uso';
      case KeyStatus.lost:
        return 'Perdida';
      case KeyStatus.damaged:
        return 'Danificada';
      case KeyStatus.maintenance:
        return 'Manutenção';
    }
  }
}

/// Tipo de controle de chave
enum KeyControlType {
  showing('showing'),
  maintenance('maintenance'),
  inspection('inspection'),
  cleaning('cleaning'),
  other('other');

  final String value;
  const KeyControlType(this.value);

  static KeyControlType fromString(String value) {
    return KeyControlType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KeyControlType.other,
    );
  }

  String get label {
    switch (this) {
      case KeyControlType.showing:
        return 'Visita';
      case KeyControlType.maintenance:
        return 'Manutenção';
      case KeyControlType.inspection:
        return 'Vistoria';
      case KeyControlType.cleaning:
        return 'Limpeza';
      case KeyControlType.other:
        return 'Outro';
    }
  }
}

/// Status de controle de chave
enum KeyControlStatus {
  checkedOut('checked_out'),
  returned('returned'),
  overdue('overdue'),
  lost('lost');

  final String value;
  const KeyControlStatus(this.value);

  static KeyControlStatus fromString(String value) {
    return KeyControlStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KeyControlStatus.checkedOut,
    );
  }

  String get label {
    switch (this) {
      case KeyControlStatus.checkedOut:
        return 'Retirada';
      case KeyControlStatus.returned:
        return 'Devolvida';
      case KeyControlStatus.overdue:
        return 'Em Atraso';
      case KeyControlStatus.lost:
        return 'Perdida';
    }
  }
}

/// Modelo de Propriedade (simplificado para chaves)
class KeyProperty {
  final String id;
  final String title;
  final String address;

  KeyProperty({
    required this.id,
    required this.title,
    required this.address,
  });

  factory KeyProperty.fromJson(Map<String, dynamic> json) {
    return KeyProperty(
      id: json['id'],
      title: json['title'] ?? '',
      address: json['address'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'address': address,
    };
  }
}

/// Modelo de Usuário (simplificado para chaves)
class KeyUser {
  final String id;
  final String name;
  final String email;

  KeyUser({
    required this.id,
    required this.name,
    required this.email,
  });

  factory KeyUser.fromJson(Map<String, dynamic> json) {
    return KeyUser(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
    );
  }
}

/// Modelo de Chave
class Key {
  final String id;
  final String name;
  final String? description;
  final KeyType type;
  final KeyStatus status;
  final String? location;
  final String? notes;
  final bool isActive;
  final String companyId;
  final String propertyId;
  final KeyProperty? property;
  final List<KeyControl>? keyControls;
  final String createdAt;
  final String updatedAt;

  Key({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.status,
    this.location,
    this.notes,
    required this.isActive,
    required this.companyId,
    required this.propertyId,
    this.property,
    this.keyControls,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Key.fromJson(Map<String, dynamic> json) {
    return Key(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'],
      type: KeyType.fromString(json['type'] ?? 'other'),
      status: KeyStatus.fromString(json['status'] ?? 'available'),
      location: json['location'],
      notes: json['notes'],
      isActive: json['isActive'] ?? true,
      companyId: json['companyId'] ?? '',
      propertyId: json['propertyId'] ?? '',
      property: json['property'] != null
          ? KeyProperty.fromJson(json['property'] as Map<String, dynamic>)
          : null,
      keyControls: json['keyControls'] != null
          ? (json['keyControls'] as List)
              .map((e) => KeyControl.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'type': type.value,
      'status': status.value,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      'isActive': isActive,
      'companyId': companyId,
      'propertyId': propertyId,
      if (property != null) 'property': property!.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// Modelo de Controle de Chave
class KeyControl {
  final String id;
  final KeyControlType type;
  final KeyControlStatus status;
  final String checkoutDate;
  final String? expectedReturnDate;
  final String? actualReturnDate;
  final String reason;
  final String? notes;
  final String? returnNotes;
  final String companyId;
  final String keyId;
  final String userId;
  final String? returnedByUserId;
  final Key? key;
  final KeyUser? user;
  final KeyUser? returnedByUser;
  final String createdAt;
  final String updatedAt;

  KeyControl({
    required this.id,
    required this.type,
    required this.status,
    required this.checkoutDate,
    this.expectedReturnDate,
    this.actualReturnDate,
    required this.reason,
    this.notes,
    this.returnNotes,
    required this.companyId,
    required this.keyId,
    required this.userId,
    this.returnedByUserId,
    this.key,
    this.user,
    this.returnedByUser,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KeyControl.fromJson(Map<String, dynamic> json) {
    return KeyControl(
      id: json['id'],
      type: KeyControlType.fromString(json['type'] ?? 'other'),
      status: KeyControlStatus.fromString(json['status'] ?? 'checked_out'),
      checkoutDate: json['checkoutDate'] ?? '',
      expectedReturnDate: json['expectedReturnDate'],
      actualReturnDate: json['actualReturnDate'],
      reason: json['reason'] ?? '',
      notes: json['notes'],
      returnNotes: json['returnNotes'],
      companyId: json['companyId'] ?? '',
      keyId: json['keyId'] ?? '',
      userId: json['userId'] ?? '',
      returnedByUserId: json['returnedByUserId'],
      key: json['key'] != null
          ? Key.fromJson(json['key'] as Map<String, dynamic>)
          : null,
      user: json['user'] != null
          ? KeyUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      returnedByUser: json['returnedByUser'] != null
          ? KeyUser.fromJson(json['returnedByUser'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'status': status.value,
      'checkoutDate': checkoutDate,
      if (expectedReturnDate != null) 'expectedReturnDate': expectedReturnDate,
      if (actualReturnDate != null) 'actualReturnDate': actualReturnDate,
      'reason': reason,
      if (notes != null) 'notes': notes,
      if (returnNotes != null) 'returnNotes': returnNotes,
      'companyId': companyId,
      'keyId': keyId,
      'userId': userId,
      if (returnedByUserId != null) 'returnedByUserId': returnedByUserId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// DTO para criar chave
class CreateKeyDto {
  final String name;
  final String? description;
  final String type;
  final String status;
  final String? location;
  final String? notes;
  final String propertyId;

  CreateKeyDto({
    required this.name,
    this.description,
    required this.type,
    required this.status,
    this.location,
    this.notes,
    required this.propertyId,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null && description!.isNotEmpty)
        'description': description,
      'type': type,
      'status': status,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'propertyId': propertyId,
    };
  }
}

/// DTO para atualizar chave
class UpdateKeyDto {
  final String? name;
  final String? description;
  final String? type;
  final String? status;
  final String? location;
  final String? notes;
  final bool? isActive;

  UpdateKeyDto({
    this.name,
    this.description,
    this.type,
    this.status,
    this.location,
    this.notes,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (type != null) map['type'] = type;
    if (status != null) map['status'] = status;
    if (location != null) map['location'] = location;
    if (notes != null) map['notes'] = notes;
    if (isActive != null) map['isActive'] = isActive;
    return map;
  }
}

/// DTO para checkout de chave
class CreateKeyControlDto {
  final String keyId;
  final String type;
  final String? expectedReturnDate;
  final String reason;
  final String? notes;

  CreateKeyControlDto({
    required this.keyId,
    required this.type,
    this.expectedReturnDate,
    required this.reason,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'keyId': keyId,
      'type': type,
      if (expectedReturnDate != null && expectedReturnDate!.isNotEmpty)
        'expectedReturnDate': expectedReturnDate,
      'reason': reason,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

/// DTO para devolução de chave
class ReturnKeyDto {
  final String? returnNotes;

  ReturnKeyDto({this.returnNotes});

  Map<String, dynamic> toJson() {
    return {
      if (returnNotes != null && returnNotes!.isNotEmpty)
        'returnNotes': returnNotes,
    };
  }
}

/// Estatísticas de chaves
class KeyStatistics {
  final int totalKeys;
  final int availableKeys;
  final int inUseKeys;
  final int overdueCount;
  final List<KeyControl> overdueKeys;

  KeyStatistics({
    required this.totalKeys,
    required this.availableKeys,
    required this.inUseKeys,
    required this.overdueCount,
    required this.overdueKeys,
  });

  factory KeyStatistics.fromJson(Map<String, dynamic> json) {
    return KeyStatistics(
      totalKeys: json['totalKeys'] ?? 0,
      availableKeys: json['availableKeys'] ?? 0,
      inUseKeys: json['inUseKeys'] ?? 0,
      overdueCount: json['overdueCount'] ?? 0,
      overdueKeys: json['overdueKeys'] != null
          ? (json['overdueKeys'] as List)
              .map((e) => KeyControl.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

/// Filtros de chaves
class KeyFilters {
  final String? status;
  final String? propertyId;
  final String? search;
  final bool? onlyMyData;

  KeyFilters({
    this.status,
    this.propertyId,
    this.search,
    this.onlyMyData,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (propertyId != null && propertyId!.isNotEmpty)
      params['propertyId'] = propertyId!;
    if (search != null && search!.isNotEmpty) params['search'] = search!;
    if (onlyMyData == true) params['onlyMyData'] = 'true';
    return params;
  }

  KeyFilters copyWith({
    String? status,
    String? propertyId,
    String? search,
    bool? onlyMyData,
  }) {
    return KeyFilters(
      status: status ?? this.status,
      propertyId: propertyId ?? this.propertyId,
      search: search ?? this.search,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }
}

/// Registro de histórico de chave
class KeyHistoryRecord {
  final String id;
  final String keyId;
  final String? userId;
  final String? keyControlId;
  final String action;
  final String description;
  final Map<String, dynamic>? previousData;
  final Map<String, dynamic>? newData;
  final Map<String, dynamic>? metadata;
  final String createdAt;
  final KeyUser? user;
  final Key? key;
  final KeyControl? keyControl;

  KeyHistoryRecord({
    required this.id,
    required this.keyId,
    this.userId,
    this.keyControlId,
    required this.action,
    required this.description,
    this.previousData,
    this.newData,
    this.metadata,
    required this.createdAt,
    this.user,
    this.key,
    this.keyControl,
  });

  factory KeyHistoryRecord.fromJson(Map<String, dynamic> json) {
    return KeyHistoryRecord(
      id: json['id'],
      keyId: json['keyId'],
      userId: json['userId'],
      keyControlId: json['keyControlId'],
      action: json['action'] ?? '',
      description: json['description'] ?? '',
      previousData: json['previousData'] != null
          ? Map<String, dynamic>.from(json['previousData'])
          : null,
      newData: json['newData'] != null
          ? Map<String, dynamic>.from(json['newData'])
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      createdAt: json['createdAt'] ?? '',
      user: json['user'] != null
          ? KeyUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      key: json['key'] != null
          ? Key.fromJson(json['key'] as Map<String, dynamic>)
          : null,
      keyControl: json['keyControl'] != null
          ? KeyControl.fromJson(json['keyControl'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Estatísticas de histórico
class KeyHistoryStatistics {
  final int totalRecords;
  final List<Map<String, dynamic>> actionStats;
  final List<KeyHistoryRecord> recentActivity;

  KeyHistoryStatistics({
    required this.totalRecords,
    required this.actionStats,
    required this.recentActivity,
  });

  factory KeyHistoryStatistics.fromJson(Map<String, dynamic> json) {
    return KeyHistoryStatistics(
      totalRecords: json['totalRecords'] ?? 0,
      actionStats: json['actionStats'] != null
          ? List<Map<String, dynamic>>.from(json['actionStats'])
          : [],
      recentActivity: json['recentActivity'] != null
          ? (json['recentActivity'] as List)
              .map((e) => KeyHistoryRecord.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

