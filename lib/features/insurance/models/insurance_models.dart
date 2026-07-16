// Modelos do módulo de Seguros (cotação de seguro fiança locatícia) —
// paridade com `insuranceService.ts` do imobx-front e com o
// `insurance.controller.ts` do backend (POST /insurance/quote,
// POST /insurance/quote-all, POST /insurance/policy).

import 'package:flutter/material.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Seguradoras integradas — valores 1:1 com o enum `provider` do backend.
enum InsuranceProvider {
  pottencial('POTTENCIAL', 'Pottencial Seguros', Color(0xFF4CAF50)),
  portoSeguro('PORTO_SEGURO', 'Porto Seguro', Color(0xFF2196F3)),
  juntoSeguros('JUNTO_SEGUROS', 'Junto Seguros', Color(0xFF8BC34A)),
  tokioMarine('TOKIO_MARINE', 'Tokio Marine', Color(0xFFF44336)),
  unknown('', 'Seguradora', Color(0xFF6B7280));

  const InsuranceProvider(this.value, this.label, this.brandColor);

  /// Valor enviado/recebido da API (ex.: `POTTENCIAL`).
  final String value;
  final String label;

  /// Cor da marca da seguradora (mesmas do web) — usada só como sinal
  /// (dot/monograma), nunca preenchendo blocos.
  final Color brandColor;

  /// Monograma exibido no lugar do logo (asset não existe no app).
  String get monogram {
    switch (this) {
      case InsuranceProvider.pottencial:
        return 'PT';
      case InsuranceProvider.portoSeguro:
        return 'PS';
      case InsuranceProvider.juntoSeguros:
        return 'JS';
      case InsuranceProvider.tokioMarine:
        return 'TM';
      case InsuranceProvider.unknown:
        return '—';
    }
  }

  static InsuranceProvider fromRaw(String? raw) {
    final v = (raw ?? '').toUpperCase().trim();
    for (final p in InsuranceProvider.values) {
      if (p.value == v && p != InsuranceProvider.unknown) return p;
    }
    return InsuranceProvider.unknown;
  }

  /// Lista de seguradoras selecionáveis (sem o fallback `unknown`).
  static const List<InsuranceProvider> selectable = [
    InsuranceProvider.pottencial,
    InsuranceProvider.portoSeguro,
    InsuranceProvider.juntoSeguros,
    InsuranceProvider.tokioMarine,
  ];
}

/// Status da cotação retornado pelo backend.
enum InsuranceQuoteStatus {
  completed,
  pending,
  error,
  unknown;

  static InsuranceQuoteStatus fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'COMPLETED':
        return InsuranceQuoteStatus.completed;
      case 'PENDING':
      case 'PROCESSING':
        return InsuranceQuoteStatus.pending;
      case 'ERROR':
      case 'FAILED':
        return InsuranceQuoteStatus.error;
      default:
        return InsuranceQuoteStatus.unknown;
    }
  }
}

/// Cotação de seguro (resposta de `POST /insurance/quote[-all]`).
class InsuranceQuote {
  final String id;
  final InsuranceProvider provider;
  final double monthlyPremium;
  final double coverageAmount;
  final InsuranceQuoteStatus status;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const InsuranceQuote({
    required this.id,
    required this.provider,
    required this.monthlyPremium,
    required this.coverageAmount,
    required this.status,
    this.createdAt,
    this.expiresAt,
  });

  bool get isCompleted => status == InsuranceQuoteStatus.completed;

  factory InsuranceQuote.fromJson(Map<String, dynamic> json) {
    return InsuranceQuote(
      id: json['id']?.toString() ?? '',
      provider: InsuranceProvider.fromRaw(json['provider']?.toString()),
      monthlyPremium:
          _toDouble(json['monthlyPremium'] ?? json['monthly_premium']),
      coverageAmount:
          _toDouble(json['coverageAmount'] ?? json['coverage_amount']),
      status: InsuranceQuoteStatus.fromRaw(json['status']?.toString()),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      expiresAt: _toDate(json['expiresAt'] ?? json['expires_at']),
    );
  }
}

/// Apólice criada a partir de uma cotação (`POST /insurance/policy`).
class InsurancePolicy {
  final String id;
  final InsuranceProvider provider;
  final String policyNumber;
  final double monthlyPremium;
  final double coverageAmount;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;

  const InsurancePolicy({
    required this.id,
    required this.provider,
    required this.policyNumber,
    required this.monthlyPremium,
    required this.coverageAmount,
    required this.status,
    this.startDate,
    this.endDate,
  });

  factory InsurancePolicy.fromJson(Map<String, dynamic> json) {
    return InsurancePolicy(
      id: json['id']?.toString() ?? '',
      provider: InsuranceProvider.fromRaw(json['provider']?.toString()),
      policyNumber:
          json['policyNumber']?.toString() ?? json['policy_number']?.toString() ?? '',
      monthlyPremium:
          _toDouble(json['monthlyPremium'] ?? json['monthly_premium']),
      coverageAmount:
          _toDouble(json['coverageAmount'] ?? json['coverage_amount']),
      status: json['status']?.toString() ?? '',
      startDate: _toDate(json['startDate'] ?? json['start_date']),
      endDate: _toDate(json['endDate'] ?? json['end_date']),
    );
  }
}

/// Payload de cotação — espelha `InsuranceQuoteRequest` do imobx-front.
/// `provider == null` ⇒ cotar em TODAS (`/insurance/quote-all`).
class InsuranceQuoteRequest {
  final InsuranceProvider? provider;
  final String propertyAddress;
  final double propertyValue;
  final double monthlyRent;
  final String tenantName;
  final String tenantDocument;
  final String? tenantEmail;
  final String? tenantPhone;

  /// Datas em `yyyy-MM-dd` (mesmo formato do input date do web).
  final String rentalStartDate;
  final String rentalEndDate;
  final String? rentalId;

  const InsuranceQuoteRequest({
    this.provider,
    required this.propertyAddress,
    required this.propertyValue,
    required this.monthlyRent,
    required this.tenantName,
    required this.tenantDocument,
    this.tenantEmail,
    this.tenantPhone,
    required this.rentalStartDate,
    required this.rentalEndDate,
    this.rentalId,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (provider != null && provider != InsuranceProvider.unknown)
        'provider': provider!.value,
      'propertyAddress': propertyAddress,
      'propertyValue': propertyValue,
      'monthlyRent': monthlyRent,
      'tenantName': tenantName,
      'tenantDocument': tenantDocument,
      if (tenantEmail != null && tenantEmail!.isNotEmpty)
        'tenantEmail': tenantEmail,
      if (tenantPhone != null && tenantPhone!.isNotEmpty)
        'tenantPhone': tenantPhone,
      'rentalStartDate': rentalStartDate,
      'rentalEndDate': rentalEndDate,
      if (rentalId != null && rentalId!.isNotEmpty) 'rentalId': rentalId,
    };
  }
}

/// Cliente encontrado na busca por CPF (`GET /clients?document=`).
class InsuranceClient {
  final String id;
  final String name;
  final String document;
  final String? email;
  final String? phone;

  const InsuranceClient({
    required this.id,
    required this.name,
    required this.document,
    this.email,
    this.phone,
  });

  factory InsuranceClient.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return InsuranceClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      document: json['document']?.toString() ?? json['cpf']?.toString() ?? '',
      email: str(json['email']),
      phone: str(json['phone'] ?? json['cellphone']),
    );
  }
}

/// Imóvel encontrado na busca por código/ID (`GET /properties/:code`).
class InsuranceProperty {
  final String id;
  final String? code;
  final String address;
  final double value;
  final double? monthlyRent;

  const InsuranceProperty({
    required this.id,
    this.code,
    required this.address,
    required this.value,
    this.monthlyRent,
  });

  factory InsuranceProperty.fromJson(Map<String, dynamic> json) {
    // `address` pode vir string ou objeto (defensivo).
    String parseAddress(dynamic v) {
      if (v is String) return v;
      if (v is Map) {
        final parts = <String>[
          for (final k in ['street', 'number', 'neighborhood', 'city', 'state'])
            if ((v[k]?.toString() ?? '').trim().isNotEmpty) v[k].toString(),
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
      final title = json['title']?.toString();
      return (title != null && title.isNotEmpty) ? title : 'Endereço não informado';
    }

    final rent = json['monthlyRent'] ?? json['rentPrice'] ?? json['rentalPrice'];
    return InsuranceProperty(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString(),
      address: parseAddress(json['address']),
      value: _toDouble(json['value'] ?? json['price'] ?? json['salePrice']),
      monthlyRent: rent == null ? null : _toDouble(rent),
    );
  }
}
