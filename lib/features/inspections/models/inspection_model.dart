/// Modelo de dados para Vistoria
class Inspection {
  final String id;
  final String title;
  final String? description;
  final InspectionType type;
  final InspectionStatus status;
  final DateTime scheduledDate;
  final DateTime? startDate;
  final DateTime? completionDate;
  final String? observations;
  final Map<String, dynamic>? checklist;
  final List<String> photos;
  final double? value;
  final String? responsibleName;
  final String? responsibleDocument;
  final String? responsiblePhone;
  final String companyId;
  final String propertyId;
  final String userId;
  final String? inspectorId;
  final bool hasFinancialApproval;
  final String? approvalId;
  final String? approvalStatus; // 'pending' | 'approved' | 'rejected'
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relacionamentos (opcionais)
  final Map<String, dynamic>? property;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? inspector;
  final List<InspectionHistoryEntry>? history;

  Inspection({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    required this.status,
    required this.scheduledDate,
    this.startDate,
    this.completionDate,
    this.observations,
    this.checklist,
    this.photos = const [],
    this.value,
    this.responsibleName,
    this.responsibleDocument,
    this.responsiblePhone,
    required this.companyId,
    required this.propertyId,
    required this.userId,
    this.inspectorId,
    this.hasFinancialApproval = false,
    this.approvalId,
    this.approvalStatus,
    required this.createdAt,
    required this.updatedAt,
    this.property,
    this.user,
    this.inspector,
    this.history,
  });

  factory Inspection.fromJson(Map<String, dynamic> json) {
    // Helper para converter valores numéricos que podem vir como string ou número
    double? _parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        return parsed;
      }
      return null;
    }

    return Inspection(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      type: InspectionType.fromString(json['type']?.toString() ?? 'entry'),
      status: InspectionStatus.fromString(
        json['status']?.toString() ?? 'scheduled',
      ),
      scheduledDate: DateTime.parse(json['scheduledDate'].toString()),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'].toString())
          : null,
      completionDate: json['completionDate'] != null
          ? DateTime.parse(json['completionDate'].toString())
          : null,
      observations: json['observations']?.toString(),
      checklist: json['checklist'] as Map<String, dynamic>?,
      photos: json['photos'] != null
          ? List<String>.from((json['photos'] as List).map((e) => e.toString()))
          : [],
      value: _parseDouble(json['value']),
      responsibleName: json['responsibleName']?.toString(),
      responsibleDocument: json['responsibleDocument']?.toString(),
      responsiblePhone: json['responsiblePhone']?.toString(),
      companyId: json['companyId']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      inspectorId: json['inspectorId']?.toString(),
      hasFinancialApproval: json['hasFinancialApproval'] as bool? ?? false,
      approvalId: json['approvalId']?.toString(),
      approvalStatus: json['approvalStatus']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      property: json['property'] as Map<String, dynamic>?,
      user: json['user'] as Map<String, dynamic>?,
      inspector: json['inspector'] as Map<String, dynamic>?,
      history: json['history'] != null
          ? (json['history'] as List)
                .map(
                  (e) => InspectionHistoryEntry.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.value,
      'status': status.value,
      'scheduledDate': scheduledDate.toIso8601String(),
      'startDate': startDate?.toIso8601String(),
      'completionDate': completionDate?.toIso8601String(),
      'observations': observations,
      'checklist': checklist,
      'photos': photos,
      'value': value,
      'responsibleName': responsibleName,
      'responsibleDocument': responsibleDocument,
      'responsiblePhone': responsiblePhone,
      'companyId': companyId,
      'propertyId': propertyId,
      'userId': userId,
      'inspectorId': inspectorId,
      'hasFinancialApproval': hasFinancialApproval,
      'approvalId': approvalId,
      'approvalStatus': approvalStatus,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Inspection copyWith({
    String? id,
    String? title,
    String? description,
    InspectionType? type,
    InspectionStatus? status,
    DateTime? scheduledDate,
    DateTime? startDate,
    DateTime? completionDate,
    String? observations,
    Map<String, dynamic>? checklist,
    List<String>? photos,
    double? value,
    String? responsibleName,
    String? responsibleDocument,
    String? responsiblePhone,
    String? companyId,
    String? propertyId,
    String? userId,
    String? inspectorId,
    bool? hasFinancialApproval,
    String? approvalId,
    String? approvalStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? property,
    Map<String, dynamic>? user,
    Map<String, dynamic>? inspector,
    List<InspectionHistoryEntry>? history,
  }) {
    return Inspection(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      status: status ?? this.status,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      startDate: startDate ?? this.startDate,
      completionDate: completionDate ?? this.completionDate,
      observations: observations ?? this.observations,
      checklist: checklist ?? this.checklist,
      photos: photos ?? this.photos,
      value: value ?? this.value,
      responsibleName: responsibleName ?? this.responsibleName,
      responsibleDocument: responsibleDocument ?? this.responsibleDocument,
      responsiblePhone: responsiblePhone ?? this.responsiblePhone,
      companyId: companyId ?? this.companyId,
      propertyId: propertyId ?? this.propertyId,
      userId: userId ?? this.userId,
      inspectorId: inspectorId ?? this.inspectorId,
      hasFinancialApproval: hasFinancialApproval ?? this.hasFinancialApproval,
      approvalId: approvalId ?? this.approvalId,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      property: property ?? this.property,
      user: user ?? this.user,
      inspector: inspector ?? this.inspector,
      history: history ?? this.history,
    );
  }
}

/// Tipos de Vistoria
enum InspectionType {
  entry('entry', 'Entrada'),
  exit('exit', 'Saída'),
  maintenance('maintenance', 'Manutenção'),
  sale('sale', 'Venda');

  final String value;
  final String label;

  const InspectionType(this.value, this.label);

  static InspectionType fromString(String? value) {
    if (value == null) return InspectionType.entry;
    try {
      return InspectionType.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return InspectionType.entry;
    }
  }
}

/// Status de Vistoria
enum InspectionStatus {
  scheduled('scheduled', 'Agendada'),
  inProgress('in_progress', 'Em Andamento'),
  completed('completed', 'Concluída'),
  cancelled('cancelled', 'Cancelada');

  final String value;
  final String label;

  const InspectionStatus(this.value, this.label);

  static InspectionStatus fromString(String? value) {
    if (value == null) return InspectionStatus.scheduled;
    try {
      return InspectionStatus.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return InspectionStatus.scheduled;
    }
  }
}

/// Entrada do histórico de vistoria
class InspectionHistoryEntry {
  final String id;
  final String inspectionId;
  final String description;
  final String userId;
  final DateTime createdAt;
  final Map<String, dynamic>? user;

  InspectionHistoryEntry({
    required this.id,
    required this.inspectionId,
    required this.description,
    required this.userId,
    required this.createdAt,
    this.user,
  });

  factory InspectionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return InspectionHistoryEntry(
      id: json['id']?.toString() ?? '',
      inspectionId: json['inspectionId']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()),
      user: json['user'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inspectionId': inspectionId,
      'description': description,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// DTO para criar vistoria
class CreateInspectionDto {
  final String title;
  final String? description;
  final InspectionType type;
  final DateTime scheduledDate;
  final String propertyId;
  final String? inspectorId;
  final double? value;
  final String? responsibleName;
  final String? responsibleDocument;
  final String? responsiblePhone;
  final String? observations;

  CreateInspectionDto({
    required this.title,
    this.description,
    required this.type,
    required this.scheduledDate,
    required this.propertyId,
    this.inspectorId,
    this.value,
    this.responsibleName,
    this.responsibleDocument,
    this.responsiblePhone,
    this.observations,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      if (description != null && description!.isNotEmpty)
        'description': description!.trim(),
      'type': type.value,
      'scheduledDate': scheduledDate.toIso8601String(),
      'propertyId': propertyId,
      if (inspectorId != null && inspectorId!.isNotEmpty)
        'inspectorId': inspectorId,
      if (value != null && value! > 0) 'value': value,
      if (responsibleName != null && responsibleName!.isNotEmpty)
        'responsibleName': responsibleName!.trim(),
      if (responsibleDocument != null && responsibleDocument!.isNotEmpty)
        'responsibleDocument': responsibleDocument!.trim(),
      if (responsiblePhone != null && responsiblePhone!.isNotEmpty)
        'responsiblePhone': responsiblePhone!.trim(),
      if (observations != null && observations!.isNotEmpty)
        'observations': observations!.trim(),
    };
  }
}

/// DTO para atualizar vistoria
class UpdateInspectionDto {
  final String? title;
  final String? description;
  final InspectionType? type;
  final InspectionStatus? status;
  final DateTime? scheduledDate;
  final DateTime? startDate;
  final DateTime? completionDate;
  final String? propertyId;
  final String? inspectorId;
  final double? value;
  final String? responsibleName;
  final String? responsibleDocument;
  final String? responsiblePhone;
  final String? observations;
  final Map<String, dynamic>? checklist;

  UpdateInspectionDto({
    this.title,
    this.description,
    this.type,
    this.status,
    this.scheduledDate,
    this.startDate,
    this.completionDate,
    this.propertyId,
    this.inspectorId,
    this.value,
    this.responsibleName,
    this.responsibleDocument,
    this.responsiblePhone,
    this.observations,
    this.checklist,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (title != null) json['title'] = title!.trim();
    if (description != null) json['description'] = description!.trim();
    if (type != null) json['type'] = type!.value;
    if (status != null) json['status'] = status!.value;
    if (scheduledDate != null)
      json['scheduledDate'] = scheduledDate!.toIso8601String();
    if (startDate != null) json['startDate'] = startDate!.toIso8601String();
    if (completionDate != null)
      json['completionDate'] = completionDate!.toIso8601String();
    if (propertyId != null) json['propertyId'] = propertyId;
    if (inspectorId != null) json['inspectorId'] = inspectorId;
    if (value != null) json['value'] = value;
    if (responsibleName != null)
      json['responsibleName'] = responsibleName!.trim();
    if (responsibleDocument != null)
      json['responsibleDocument'] = responsibleDocument!.trim();
    if (responsiblePhone != null)
      json['responsiblePhone'] = responsiblePhone!.trim();
    if (observations != null) json['observations'] = observations!.trim();
    if (checklist != null) json['checklist'] = checklist;

    return json;
  }
}

/// Filtros para listagem de vistorias
class InspectionFilters {
  final String? title;
  final InspectionStatus? status;
  final InspectionType? type;
  final String? propertyId;
  final String? inspectorId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? page;
  final int? limit;
  final bool? onlyMyData;

  InspectionFilters({
    this.title,
    this.status,
    this.type,
    this.propertyId,
    this.inspectorId,
    this.startDate,
    this.endDate,
    this.page,
    this.limit,
    this.onlyMyData,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{};

    if (title != null && title!.isNotEmpty) params['title'] = title!;
    if (status != null) params['status'] = status!.value;
    if (type != null) params['type'] = type!.value;
    if (propertyId != null && propertyId!.isNotEmpty)
      params['propertyId'] = propertyId!;
    if (inspectorId != null && inspectorId!.isNotEmpty)
      params['inspectorId'] = inspectorId!;
    if (startDate != null) params['dataInicial'] = startDate!.toIso8601String();
    if (endDate != null) params['dataFinal'] = endDate!.toIso8601String();
    if (page != null) params['page'] = page!.toString();
    if (limit != null) params['limit'] = limit!.toString();
    if (onlyMyData != null && onlyMyData!) params['onlyMyData'] = 'true';

    return params;
  }

  InspectionFilters copyWith({
    String? title,
    InspectionStatus? status,
    InspectionType? type,
    String? propertyId,
    String? inspectorId,
    DateTime? startDate,
    DateTime? endDate,
    int? page,
    int? limit,
    bool? onlyMyData,
  }) {
    return InspectionFilters(
      title: title ?? this.title,
      status: status ?? this.status,
      type: type ?? this.type,
      propertyId: propertyId ?? this.propertyId,
      inspectorId: inspectorId ?? this.inspectorId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }
}

/// Resposta de listagem de vistorias
class InspectionListResponse {
  final List<Inspection> inspections;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  InspectionListResponse({
    required this.inspections,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory InspectionListResponse.fromJson(Map<String, dynamic> json) {
    final inspectionsList = json['inspections'] as List<dynamic>? ?? [];

    return InspectionListResponse(
      inspections: inspectionsList
          .map((e) => Inspection.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
      totalPages: json['totalPages'] as int? ?? 1,
    );
  }
}

/// DTO para solicitar aprovação financeira
class CreateInspectionApprovalDto {
  final String inspectionId;
  final double amount;
  final String? notes;

  CreateInspectionApprovalDto({
    required this.inspectionId,
    required this.amount,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'inspectionId': inspectionId,
      'amount': amount,
      if (notes != null && notes!.isNotEmpty) 'notes': notes!.trim(),
    };
  }
}

/// DTO para adicionar entrada ao histórico
class CreateInspectionHistoryDto {
  final String description;

  CreateInspectionHistoryDto({required this.description});

  Map<String, dynamic> toJson() {
    return {'description': description.trim()};
  }
}
