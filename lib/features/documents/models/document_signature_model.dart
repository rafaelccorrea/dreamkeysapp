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
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
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

  /// Ainda dá para assinar pelo link (aguardando ou só visualizado).
  bool get isSignable =>
      this == DocumentSignatureStatus.pending ||
      this == DocumentSignatureStatus.viewed;

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

/// Tipo de signatário na tela "Enviar para assinatura" — paridade com
/// `SignerType` do web (`external` | `client` | `user`).
enum SignerKind {
  external('external', 'Signatário externo'),
  client('client', 'Cliente do sistema'),
  user('user', 'Usuário do sistema');

  final String value;
  final String label;

  const SignerKind(this.value, this.label);
}

/// Um signatário do lote enviado em
/// `POST /documents/:documentId/signatures/batch`.
class SignatureSignerInput {
  final String? clientId;
  final String? userId;
  final String signerName;
  final String signerEmail;
  final String? signerPhone;
  final String? signerCpf;

  const SignatureSignerInput({
    this.clientId,
    this.userId,
    required this.signerName,
    required this.signerEmail,
    this.signerPhone,
    this.signerCpf,
  });

  Map<String, dynamic> toJson() {
    return {
      if (clientId != null && clientId!.isNotEmpty) 'clientId': clientId,
      if (userId != null && userId!.isNotEmpty) 'userId': userId,
      'signerName': signerName,
      'signerEmail': signerEmail,
      if (signerPhone != null && signerPhone!.isNotEmpty)
        'signerPhone': signerPhone,
      if (signerCpf != null && signerCpf!.isNotEmpty) 'signerCpf': signerCpf,
    };
  }
}

/// Resposta do envio em lote: quantas assinaturas nasceram e os erros por
/// signatário (o back cria as que der e devolve o resto em `errors`).
class BatchSignatureResult {
  final List<DocumentSignature> signatures;
  final int total;
  final int success;
  final List<String> errors;

  BatchSignatureResult({
    required this.signatures,
    required this.total,
    required this.success,
    required this.errors,
  });

  factory BatchSignatureResult.fromJson(Map<String, dynamic> json) {
    final rawSignatures = json['signatures'];
    final rawErrors = json['errors'];
    final errors = <String>[];
    if (rawErrors is List) {
      for (final e in rawErrors) {
        if (e is Map) {
          // O back devolve `{ signer: SignerDto, error }` — o signatário é um
          // objeto; mostra nome ou e-mail, nunca o mapa cru.
          final signer = e['signer'];
          final who = (signer is Map
                  ? (signer['signerName'] ?? signer['signerEmail'] ?? '')
                  : (signer ?? e['signerEmail'] ?? ''))
              .toString();
          final why = (e['error'] ?? e['message'] ?? '').toString();
          errors.add(who.isEmpty ? why : '$who: $why');
        } else if (e != null) {
          errors.add(e.toString());
        }
      }
    }
    final signatures = <DocumentSignature>[];
    if (rawSignatures is List) {
      for (final s in rawSignatures) {
        if (s is Map) {
          try {
            signatures.add(
              DocumentSignature.fromJson(Map<String, dynamic>.from(s)),
            );
          } catch (_) {}
        }
      }
    }
    return BatchSignatureResult(
      signatures: signatures,
      total: int.tryParse(json['total']?.toString() ?? '') ??
          signatures.length,
      success: int.tryParse(json['success']?.toString() ?? '') ??
          signatures.length,
      errors: errors,
    );
  }
}

/// Usuário ativo da empresa oferecido como signatário (`GET /admin/users`
/// com `active=true&allCompanyUsers=true`, igual ao web).
class SignerUserOption {
  final String id;
  final String name;
  final String email;
  final String? phone;

  SignerUserOption({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
  });

  factory SignerUserOption.fromJson(Map<String, dynamic> json) {
    return SignerUserOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
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

