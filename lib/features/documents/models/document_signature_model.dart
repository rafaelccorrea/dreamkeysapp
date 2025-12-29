/// Modelo de Assinatura de Documento
class DocumentSignature {
  final String id;
  final String documentId;
  final String companyId;
  final String? clientId;
  final String? userId;
  final DocumentSignatureStatus status;
  final String signerName;
  final String signerEmail;
  final String? signerPhone;
  final String? signerCpf;
  final DateTime? expiresAt;
  final DateTime? viewedAt;
  final DateTime? signedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final String? assinafyDocumentId;
  final String? assinafySignerId;
  final String? assinafyAssignmentId;
  final String? signatureUrl;
  final String? signerAccessCode;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Dados relacionados
  final DocumentSignatureDocument? document;
  final DocumentSignatureClient? client;
  final DocumentSignatureUser? user;

  DocumentSignature({
    required this.id,
    required this.documentId,
    required this.companyId,
    this.clientId,
    this.userId,
    required this.status,
    required this.signerName,
    required this.signerEmail,
    this.signerPhone,
    this.signerCpf,
    this.expiresAt,
    this.viewedAt,
    this.signedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.assinafyDocumentId,
    this.assinafySignerId,
    this.assinafyAssignmentId,
    this.signatureUrl,
    this.signerAccessCode,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.document,
    this.client,
    this.user,
  });

  factory DocumentSignature.fromJson(Map<String, dynamic> json) {
    return DocumentSignature(
      id: json['id']?.toString() ?? '',
      documentId: json['documentId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      clientId: json['clientId']?.toString(),
      userId: json['userId']?.toString(),
      status: DocumentSignatureStatus.fromString(
        json['status']?.toString() ?? 'pending',
      ),
      signerName: json['signerName']?.toString() ?? '',
      signerEmail: json['signerEmail']?.toString() ?? '',
      signerPhone: json['signerPhone']?.toString(),
      signerCpf: json['signerCpf']?.toString(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null,
      viewedAt: json['viewedAt'] != null
          ? DateTime.parse(json['viewedAt'])
          : null,
      signedAt: json['signedAt'] != null
          ? DateTime.parse(json['signedAt'])
          : null,
      rejectedAt: json['rejectedAt'] != null
          ? DateTime.parse(json['rejectedAt'])
          : null,
      rejectionReason: json['rejectionReason']?.toString(),
      assinafyDocumentId: json['assinafyDocumentId']?.toString(),
      assinafySignerId: json['assinafySignerId']?.toString(),
      assinafyAssignmentId: json['assinafyAssignmentId']?.toString(),
      signatureUrl: json['signatureUrl']?.toString(),
      signerAccessCode: json['signerAccessCode']?.toString(),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      document: json['document'] != null
          ? DocumentSignatureDocument.fromJson(json['document'])
          : null,
      client: json['client'] != null
          ? DocumentSignatureClient.fromJson(json['client'])
          : null,
      user: json['user'] != null
          ? DocumentSignatureUser.fromJson(json['user'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentId': documentId,
      'companyId': companyId,
      'clientId': clientId,
      'userId': userId,
      'status': status.value,
      'signerName': signerName,
      'signerEmail': signerEmail,
      'signerPhone': signerPhone,
      'signerCpf': signerCpf,
      'expiresAt': expiresAt?.toIso8601String(),
      'viewedAt': viewedAt?.toIso8601String(),
      'signedAt': signedAt?.toIso8601String(),
      'rejectedAt': rejectedAt?.toIso8601String(),
      'rejectionReason': rejectionReason,
      'assinafyDocumentId': assinafyDocumentId,
      'assinafySignerId': assinafySignerId,
      'assinafyAssignmentId': assinafyAssignmentId,
      'signatureUrl': signatureUrl,
      'signerAccessCode': signerAccessCode,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Status da Assinatura
enum DocumentSignatureStatus {
  pending('pending', 'Aguardando'),
  viewed('viewed', 'Visualizado'),
  signed('signed', 'Assinado'),
  rejected('rejected', 'Rejeitado'),
  expired('expired', 'Expirado'),
  cancelled('cancelled', 'Cancelado');

  final String value;
  final String label;

  const DocumentSignatureStatus(this.value, this.label);

  static DocumentSignatureStatus fromString(String value) {
    return DocumentSignatureStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DocumentSignatureStatus.pending,
    );
  }
}

/// Documento relacionado à assinatura
class DocumentSignatureDocument {
  final String id;
  final String title;
  final String originalName;

  DocumentSignatureDocument({
    required this.id,
    required this.title,
    required this.originalName,
  });

  factory DocumentSignatureDocument.fromJson(Map<String, dynamic> json) {
    return DocumentSignatureDocument(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
    );
  }
}

/// Cliente relacionado à assinatura
class DocumentSignatureClient {
  final String id;
  final String name;
  final String email;

  DocumentSignatureClient({
    required this.id,
    required this.name,
    required this.email,
  });

  factory DocumentSignatureClient.fromJson(Map<String, dynamic> json) {
    return DocumentSignatureClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

/// Usuário relacionado à assinatura
class DocumentSignatureUser {
  final String id;
  final String name;
  final String email;

  DocumentSignatureUser({
    required this.id,
    required this.name,
    required this.email,
  });

  factory DocumentSignatureUser.fromJson(Map<String, dynamic> json) {
    return DocumentSignatureUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

/// Estatísticas de Assinaturas
class DocumentSignatureStats {
  final int total;
  final int pending;
  final int viewed;
  final int signed;
  final int rejected;
  final int expired;

  DocumentSignatureStats({
    required this.total,
    required this.pending,
    required this.viewed,
    required this.signed,
    required this.rejected,
    required this.expired,
  });

  factory DocumentSignatureStats.fromJson(Map<String, dynamic> json) {
    return DocumentSignatureStats(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      viewed: json['viewed'] ?? 0,
      signed: json['signed'] ?? 0,
      rejected: json['rejected'] ?? 0,
      expired: json['expired'] ?? 0,
    );
  }
}

