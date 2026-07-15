// Modelos de Unidades (filiais) — espelham `UnitResponseDto` do backend
// (`imobx/src/units/dto/unit.dto.ts`) e o `unitsApi` do imobx-front.

/// Paleta de identificação visual das unidades (1:1 com `UnitsPage.tsx`).
const List<int> kUnitColorValues = [
  0xFF6366F1,
  0xFF8B5CF6,
  0xFF06B6D4,
  0xFF3B82F6,
  0xFF10B981,
  0xFFF59E0B,
  0xFFEF4444,
  0xFFEC4899,
  0xFF14B8A6,
  0xFFF97316,
];

String _asString(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Gestor vinculado a uma unidade.
class UnitManager {
  final String userId;
  final String name;
  final String? email;
  final String? avatar;

  const UnitManager({
    required this.userId,
    required this.name,
    this.email,
    this.avatar,
  });

  factory UnitManager.fromJson(Map<String, dynamic> json) {
    return UnitManager(
      userId: _asString(json['userId'] ?? json['id']),
      name: _asString(json['name'], 'Sem nome'),
      email: json['email']?.toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

/// Unidade (filial) da empresa.
class OrgUnit {
  final String id;
  final String name;
  final String? description;

  /// Cor hex (`#RRGGBB`) definida no web; cai no índigo padrão se inválida.
  final String color;
  final bool isActive;
  final int teamCount;
  final List<UnitManager> managers;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OrgUnit({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.isActive,
    required this.teamCount,
    required this.managers,
    this.createdAt,
    this.updatedAt,
  });

  factory OrgUnit.fromJson(Map<String, dynamic> json) {
    final rawManagers = json['managers'];
    return OrgUnit(
      id: _asString(json['id']),
      name: _asString(json['name'], 'Unidade'),
      description: json['description']?.toString(),
      color: _asString(json['color'], '#6366F1'),
      isActive: json['isActive'] == true ||
          json['isActive']?.toString() == 'true',
      teamCount: _toInt(json['teamCount']),
      managers: rawManagers is List
          ? rawManagers
              .whereType<Map>()
              .map((m) => UnitManager.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      createdAt: _toDate(json['createdAt']),
      updatedAt: _toDate(json['updatedAt']),
    );
  }

  /// Cor como valor ARGB (0xFF + hex), tolerante a `#RGB`/inválido.
  int get colorValue {
    var hex = color.replaceAll('#', '').trim();
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return kUnitColorValues.first;
    return int.tryParse('FF$hex', radix: 16) ?? kUnitColorValues.first;
  }
}

/// Membro da empresa (rota pública `/users/company-members` — qualquer
/// utilizador autenticado). Usado no seletor de gestores da unidade.
class CompanyMember {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? avatar;

  const CompanyMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
  });

  factory CompanyMember.fromJson(Map<String, dynamic> json) {
    return CompanyMember(
      id: _asString(json['id']),
      name: _asString(json['name'], 'Sem nome'),
      email: _asString(json['email']),
      role: _asString(json['role'], 'user'),
      avatar: json['avatar']?.toString(),
    );
  }
}
