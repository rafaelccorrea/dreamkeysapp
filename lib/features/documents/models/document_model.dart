/// Modelo de Documento
class Document {
  final String id;
  final String originalName;
  final String fileName;
  final String fileUrl;
  final int fileSize;
  final String mimeType;
  final String fileExtension;
  final DocumentType type;
  final DocumentStatus status;
  final String? title;
  final String? description;
  final List<String>? tags;
  final String? notes;
  final DateTime? expiryDate;
  final String companyId;
  final String uploadedById;
  final String? clientId;
  final String? propertyId;
  final bool isEncrypted;
  final DateTime? approvedAt;
  final String? approvedById;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool? isForSignature;
  final DocumentSignaturesInfo? signatures;

  // Dados relacionados (quando vem com detalhes)
  final DocumentClient? client;
  final DocumentProperty? property;
  final DocumentUser? uploadedBy;
  final DocumentUser? approvedBy;

  Document({
    required this.id,
    required this.originalName,
    required this.fileName,
    required this.fileUrl,
    required this.fileSize,
    required this.mimeType,
    required this.fileExtension,
    required this.type,
    required this.status,
    this.title,
    this.description,
    this.tags,
    this.notes,
    this.expiryDate,
    required this.companyId,
    required this.uploadedById,
    this.clientId,
    this.propertyId,
    required this.isEncrypted,
    this.approvedAt,
    this.approvedById,
    required this.createdAt,
    required this.updatedAt,
    this.isForSignature,
    this.signatures,
    this.client,
    this.property,
    this.uploadedBy,
    this.approvedBy,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      fileUrl: json['fileUrl']?.toString() ?? '',
      fileSize: _parseInt(json['fileSize']) ?? 0,
      mimeType: json['mimeType']?.toString() ?? '',
      fileExtension: json['fileExtension']?.toString() ?? '',
      type: DocumentType.fromString(json['type']?.toString() ?? 'other'),
      status: DocumentStatus.fromString(json['status']?.toString() ?? 'active'),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
      notes: json['notes']?.toString(),
      expiryDate: json['expiryDate'] != null
          ? DateTime.parse(json['expiryDate'])
          : null,
      companyId: json['companyId']?.toString() ?? '',
      uploadedById: json['uploadedById']?.toString() ?? '',
      clientId: json['clientId']?.toString(),
      propertyId: json['propertyId']?.toString(),
      isEncrypted: json['isEncrypted'] == true,
      approvedAt: json['approvedAt'] != null
          ? DateTime.parse(json['approvedAt'])
          : null,
      approvedById: json['approvedById']?.toString(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      isForSignature: json['isForSignature'] == true,
      signatures: json['signatures'] != null
          ? DocumentSignaturesInfo.fromJson(json['signatures'])
          : null,
      client: json['client'] != null
          ? DocumentClient.fromJson(json['client'])
          : null,
      property: json['property'] != null
          ? DocumentProperty.fromJson(json['property'])
          : null,
      uploadedBy: json['uploadedBy'] != null
          ? DocumentUser.fromJson(json['uploadedBy'])
          : null,
      approvedBy: json['approvedBy'] != null
          ? DocumentUser.fromJson(json['approvedBy'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalName': originalName,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'fileExtension': fileExtension,
      'type': type.value,
      'status': status.value,
      'title': title,
      'description': description,
      'tags': tags,
      'notes': notes,
      'expiryDate': expiryDate?.toIso8601String(),
      'companyId': companyId,
      'uploadedById': uploadedById,
      'clientId': clientId,
      'propertyId': propertyId,
      'isEncrypted': isEncrypted,
      'approvedAt': approvedAt?.toIso8601String(),
      'approvedById': approvedById,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isForSignature': isForSignature,
    };
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Tipo de Documento
enum DocumentType {
  contract('contract', 'Contrato'),
  identity('identity', 'Identidade'),
  proofOfAddress('proof_of_address', 'Comprovante de Endereço'),
  proofOfIncome('proof_of_income', 'Comprovante de Renda'),
  deed('deed', 'Escritura'),
  registration('registration', 'Registro'),
  taxDocument('tax_document', 'Documento Fiscal'),
  inspectionReport('inspection_report', 'Laudo Vistoria'),
  appraisal('appraisal', 'Avaliação'),
  photo('photo', 'Foto'),
  other('other', 'Outro');

  final String value;
  final String label;

  const DocumentType(this.value, this.label);

  static DocumentType fromString(String value) {
    return DocumentType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DocumentType.other,
    );
  }
}

/// Status do Documento
enum DocumentStatus {
  active('active', 'Ativo'),
  archived('archived', 'Arquivado'),
  deleted('deleted', 'Deletado'),
  pendingReview('pending_review', 'Pendente de Revisão'),
  approved('approved', 'Aprovado'),
  rejected('rejected', 'Rejeitado');

  final String value;
  final String label;

  const DocumentStatus(this.value, this.label);

  static DocumentStatus fromString(String value) {
    return DocumentStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DocumentStatus.active,
    );
  }
}

/// Informações de Assinaturas do Documento
class DocumentSignaturesInfo {
  final int total;
  final int pending;
  final int signed;
  final int rejected;

  DocumentSignaturesInfo({
    required this.total,
    required this.pending,
    required this.signed,
    required this.rejected,
  });

  factory DocumentSignaturesInfo.fromJson(Map<String, dynamic> json) {
    return DocumentSignaturesInfo(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      signed: json['signed'] ?? 0,
      rejected: json['rejected'] ?? 0,
    );
  }
}

/// Cliente relacionado ao documento
class DocumentClient {
  final String id;
  final String name;
  final String? email;
  final String? phone;

  DocumentClient({
    required this.id,
    required this.name,
    this.email,
    this.phone,
  });

  factory DocumentClient.fromJson(Map<String, dynamic> json) {
    return DocumentClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

/// Propriedade relacionada ao documento
class DocumentProperty {
  final String id;
  final String title;
  final String? code;
  final String? address;

  DocumentProperty({
    required this.id,
    required this.title,
    this.code,
    this.address,
  });

  factory DocumentProperty.fromJson(Map<String, dynamic> json) {
    return DocumentProperty(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      code: json['code']?.toString(),
      address: json['address']?.toString(),
    );
  }
}

/// Usuário relacionado ao documento
class DocumentUser {
  final String id;
  final String name;
  final String? email;

  DocumentUser({required this.id, required this.name, this.email});

  factory DocumentUser.fromJson(Map<String, dynamic> json) {
    return DocumentUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
    );
  }
}
