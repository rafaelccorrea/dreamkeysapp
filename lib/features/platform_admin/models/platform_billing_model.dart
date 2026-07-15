// Modelos da Cobrança do Sistema (Master) — espelham o
// `platformSettingsService` do imobx-front e o
// `platform-settings.controller.ts` do backend (rotas @Roles(MASTER)).

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// Regime de cobrança de uma conta titular (1:1 com `BillingRegime` do back).
enum BillingRegime {
  managed,
  selfServe,
  unknown;

  static BillingRegime fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'managed':
        return BillingRegime.managed;
      case 'self_serve':
      case 'selfserve':
        return BillingRegime.selfServe;
      default:
        return BillingRegime.unknown;
    }
  }

  /// Valor exato aceito pelo backend em `PATCH .../billing-regime`.
  String get apiValue =>
      this == BillingRegime.managed ? 'managed' : 'self_serve';

  String get label {
    switch (this) {
      case BillingRegime.managed:
        return 'Gerenciada';
      case BillingRegime.selfServe:
        return 'Comum';
      case BillingRegime.unknown:
        return '—';
    }
  }
}

/// `GET /platform-settings` — config global da plataforma.
class PlatformSettings {
  final String id;
  final bool billingEnforcementEnabled;
  final DateTime? billingEnforcementEnabledAt;
  final int managedTrialDays;
  final int billingGraceDays;

  const PlatformSettings({
    required this.id,
    required this.billingEnforcementEnabled,
    this.billingEnforcementEnabledAt,
    required this.managedTrialDays,
    required this.billingGraceDays,
  });

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    return PlatformSettings(
      id: json['id']?.toString() ?? '',
      billingEnforcementEnabled: json['billingEnforcementEnabled'] == true,
      billingEnforcementEnabledAt:
          _toDate(json['billingEnforcementEnabledAt']),
      managedTrialDays: _toInt(json['managedTrialDays'], 0),
      billingGraceDays: _toInt(json['billingGraceDays'], 10),
    );
  }
}

/// `GET /platform-settings/accounts` — conta titular + regime de cobrança.
class OwnerAccount {
  final String id;
  final String name;
  final String email;
  final String role;
  final BillingRegime billingRegime;
  final DateTime? managedBillingUntil;

  const OwnerAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.billingRegime,
    this.managedBillingUntil,
  });

  bool get isMaster => role.trim().toLowerCase() == 'master';
  bool get isManaged => billingRegime == BillingRegime.managed;

  /// Cobrança ativa nesta conta: gerenciada com prazo já vencido
  /// (mesma regra `isAccountBlocked` da BillingControlPage do web).
  bool get isBlocked =>
      isManaged &&
      managedBillingUntil != null &&
      !managedBillingUntil!.isAfter(DateTime.now());

  /// Iniciais para o avatar (primeiro + último nome).
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory OwnerAccount.fromJson(Map<String, dynamic> json) {
    return OwnerAccount(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      billingRegime: BillingRegime.fromRaw(json['billingRegime']?.toString()),
      managedBillingUntil: _toDate(json['managedBillingUntil']),
    );
  }
}

/// Filtro segmentado da lista de contas (paridade com o Segmented do web).
enum BillingAccountFilter { all, managed, blocked, common }
