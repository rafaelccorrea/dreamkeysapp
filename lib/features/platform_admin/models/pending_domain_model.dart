// Modelos de Domínios de sites públicos (Master) — espelham
// `publicSiteConfigApi.listPendingDomains` do imobx-front e o
// `public-site-config-admin.controller.ts` (@Roles(MASTER)).

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Status do domínio próprio (1:1 com `PublicSiteDomainStatus`).
enum PublicSiteDomainStatus {
  pendingDns,
  pendingReview,
  active,
  disabled,
  unknown;

  static PublicSiteDomainStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending_dns':
        return PublicSiteDomainStatus.pendingDns;
      case 'pending_review':
        return PublicSiteDomainStatus.pendingReview;
      case 'active':
        return PublicSiteDomainStatus.active;
      case 'disabled':
        return PublicSiteDomainStatus.disabled;
      default:
        return PublicSiteDomainStatus.unknown;
    }
  }

  /// Rótulos idênticos ao `publicSiteLabels.ts` do web.
  String get label {
    switch (this) {
      case PublicSiteDomainStatus.pendingDns:
        return 'Aguardando DNS';
      case PublicSiteDomainStatus.pendingReview:
        return 'Revisão manual';
      case PublicSiteDomainStatus.active:
        return 'Ativo';
      case PublicSiteDomainStatus.disabled:
        return 'Desativado';
      case PublicSiteDomainStatus.unknown:
        return '—';
    }
  }
}

/// Item da fila `GET /public-site-config/admin/pending-domains`.
class PendingCustomDomain {
  final String companyId;
  final String companyName;
  final String? customDomain;
  final PublicSiteDomainStatus domainStatus;
  final DateTime? updatedAt;

  const PendingCustomDomain({
    required this.companyId,
    required this.companyName,
    this.customDomain,
    required this.domainStatus,
    this.updatedAt,
  });

  factory PendingCustomDomain.fromJson(Map<String, dynamic> json) {
    return PendingCustomDomain(
      companyId: json['companyId']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? '',
      customDomain: json['customDomain']?.toString(),
      domainStatus:
          PublicSiteDomainStatus.fromRaw(json['domainStatus']?.toString()),
      updatedAt: _toDate(json['updatedAt']),
    );
  }
}
