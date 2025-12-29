import 'document_model.dart';

/// Modelo de Token de Upload
class UploadToken {
  final String id;
  final String token;
  final String uploadUrl;
  final String clientId;
  final String clientName;
  final String clientCpfMasked;
  final DateTime expiresAt;
  final UploadTokenStatus status;
  final int documentsUploaded;
  final String? notes;
  final DateTime createdAt;

  UploadToken({
    required this.id,
    required this.token,
    required this.uploadUrl,
    required this.clientId,
    required this.clientName,
    required this.clientCpfMasked,
    required this.expiresAt,
    required this.status,
    required this.documentsUploaded,
    this.notes,
    required this.createdAt,
  });

  factory UploadToken.fromJson(Map<String, dynamic> json) {
    return UploadToken(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      uploadUrl: json['uploadUrl']?.toString() ?? '',
      clientId: json['clientId']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      clientCpfMasked: json['clientCpfMasked']?.toString() ?? '',
      expiresAt: DateTime.parse(json['expiresAt']),
      status: UploadTokenStatus.fromString(
        json['status']?.toString() ?? 'active',
      ),
      documentsUploaded: json['documentsUploaded'] ?? 0,
      notes: json['notes']?.toString(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'token': token,
      'uploadUrl': uploadUrl,
      'clientId': clientId,
      'clientName': clientName,
      'clientCpfMasked': clientCpfMasked,
      'expiresAt': expiresAt.toIso8601String(),
      'status': status.value,
      'documentsUploaded': documentsUploaded,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isActive => status == UploadTokenStatus.active && !isExpired;
}

/// Status do Token de Upload
enum UploadTokenStatus {
  active('active', 'Ativo'),
  expired('expired', 'Expirado'),
  used('used', 'Usado'),
  revoked('revoked', 'Revogado');

  final String value;
  final String label;

  const UploadTokenStatus(this.value, this.label);

  static UploadTokenStatus fromString(String value) {
    return UploadTokenStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UploadTokenStatus.active,
    );
  }
}

/// Informações do Token (para validação pública)
class UploadTokenInfo {
  final String clientName;
  final String clientCpfMasked;
  final DateTime expiresAt;
  final bool isValid;

  UploadTokenInfo({
    required this.clientName,
    required this.clientCpfMasked,
    required this.expiresAt,
    required this.isValid,
  });

  factory UploadTokenInfo.fromJson(Map<String, dynamic> json) {
    return UploadTokenInfo(
      clientName: json['clientName']?.toString() ?? '',
      clientCpfMasked: json['clientCpfMasked']?.toString() ?? '',
      expiresAt: DateTime.parse(json['expiresAt']),
      isValid: json['isValid'] == true,
    );
  }
}

/// Resposta de Validação de CPF
class CpfValidationResponse {
  final bool valid;
  final String? clientName;
  final DateTime? expiresAt;
  final String? message;

  CpfValidationResponse({
    required this.valid,
    this.clientName,
    this.expiresAt,
    this.message,
  });

  factory CpfValidationResponse.fromJson(Map<String, dynamic> json) {
    return CpfValidationResponse(
      valid: json['valid'] == true,
      clientName: json['clientName']?.toString(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null,
      message: json['message']?.toString(),
    );
  }
}

/// Resposta de Upload Público
class PublicUploadResponse {
  final String id;
  final String originalName;
  final DocumentType type;
  final String? title;
  final int fileSize;
  final String mimeType;
  final DocumentStatus status;
  final DateTime createdAt;

  PublicUploadResponse({
    required this.id,
    required this.originalName,
    required this.type,
    this.title,
    required this.fileSize,
    required this.mimeType,
    required this.status,
    required this.createdAt,
  });

  factory PublicUploadResponse.fromJson(Map<String, dynamic> json) {
    return PublicUploadResponse(
      id: json['id']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
      type: DocumentType.fromString(json['type']?.toString() ?? 'other'),
      title: json['title']?.toString(),
      fileSize: json['fileSize'] ?? 0,
      mimeType: json['mimeType']?.toString() ?? '',
      status: DocumentStatus.fromString(
        json['status']?.toString() ?? 'active',
      ),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

