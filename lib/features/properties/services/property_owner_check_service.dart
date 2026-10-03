import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';

/// Imóvel já cadastrado para o mesmo proprietário (item de `properties` do
/// `POST /properties/owner-check`), com o motivo do casamento.
class PropertyOwnerMatch {
  final PropertyDuplicateCandidate property;

  /// `'document'` (CPF/CNPJ) ou `'phone'` (telefone), como o back devolve.
  final String? matchReason;

  const PropertyOwnerMatch({required this.property, this.matchReason});

  String? get matchLabel => switch (matchReason) {
        'document' => 'CPF/CNPJ',
        'phone' => 'Telefone',
        _ => null,
      };
}

class PropertyOwnerCheckResult {
  final bool hasExisting;
  final List<PropertyOwnerMatch> properties;

  const PropertyOwnerCheckResult({
    required this.hasExisting,
    required this.properties,
  });

  /// Lê a resposta do back (`{ hasExisting, properties: [...] }`).
  factory PropertyOwnerCheckResult.fromJson(Map<String, dynamic> json) {
    final raw = json['properties'];
    final out = <PropertyOwnerMatch>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final c = PropertyDuplicateCandidate.fromJson(m);
        if (c.id.isEmpty) continue;
        final reason = m['matchReason']?.toString();
        out.add(PropertyOwnerMatch(property: c, matchReason: reason));
      }
    }
    return PropertyOwnerCheckResult(
      hasExisting: json['hasExisting'] == true || out.isNotEmpty,
      properties: out,
    );
  }
}

/// Corpo do `POST /properties/owner-check` — `buildOwnerCheckPayload` do web:
/// nome e telefone aparados, documento só com dígitos (omitido se vazio).
Map<String, dynamic> buildOwnerCheckPayload({
  required String ownerName,
  required String ownerPhone,
  required String ownerDocument,
}) {
  final doc = ownerDocument.replaceAll(RegExp(r'\D'), '').trim();
  return {
    'ownerName': ownerName.trim(),
    'ownerPhone': ownerPhone.trim(),
    if (doc.isNotEmpty) 'ownerDocument': doc,
  };
}

/// Chave de "já vi e decidi seguir" — `buildOwnerAckKey` do web: mudou nome,
/// telefone ou documento, a checagem volta a valer.
String buildOwnerAckKey({
  required String ownerName,
  required String ownerPhone,
  required String ownerDocument,
}) =>
    [
      ownerName.trim(),
      ownerPhone.replaceAll(RegExp(r'\D'), ''),
      ownerDocument.replaceAll(RegExp(r'\D'), ''),
    ].join('|');

/// `checkOwnerForCreation` do web (`propertyApi.ts` ~554).
class PropertyOwnerCheckService {
  PropertyOwnerCheckService._();
  static final PropertyOwnerCheckService instance =
      PropertyOwnerCheckService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<PropertyOwnerCheckResult>> check(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/properties/owner-check',
        body: payload,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: PropertyOwnerCheckResult.fromJson(res.data!),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao verificar imóveis do proprietário',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_OWNER_CHECK] $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
