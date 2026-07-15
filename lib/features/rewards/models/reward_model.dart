// Modelos do módulo **Prêmios & Resgates** (gamificação) — espelham
// `rewards.types.ts` do imobx-front e as respostas de `/rewards/*` do backend
// (rewards.controller.ts). fromJson defensivo: tolera null/string/number.

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic>? _toMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Categoria do prêmio (1:1 com `RewardCategory` do web).
enum RewardCategory {
  monetary,
  timeOff,
  gift,
  experience,
  recognition,
  other;

  static RewardCategory fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'monetary':
        return RewardCategory.monetary;
      case 'time_off':
      case 'timeoff':
        return RewardCategory.timeOff;
      case 'gift':
        return RewardCategory.gift;
      case 'experience':
        return RewardCategory.experience;
      case 'recognition':
        return RewardCategory.recognition;
      default:
        return RewardCategory.other;
    }
  }

  /// Valor exato enviado à API.
  String get raw {
    switch (this) {
      case RewardCategory.monetary:
        return 'monetary';
      case RewardCategory.timeOff:
        return 'time_off';
      case RewardCategory.gift:
        return 'gift';
      case RewardCategory.experience:
        return 'experience';
      case RewardCategory.recognition:
        return 'recognition';
      case RewardCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case RewardCategory.monetary:
        return 'Monetário';
      case RewardCategory.timeOff:
        return 'Folga';
      case RewardCategory.gift:
        return 'Presente';
      case RewardCategory.experience:
        return 'Experiência';
      case RewardCategory.recognition:
        return 'Reconhecimento';
      case RewardCategory.other:
        return 'Outro';
    }
  }

  /// Emoji padrão da categoria (paridade `getDefaultIcon` do web).
  String get defaultIcon {
    switch (this) {
      case RewardCategory.monetary:
        return '💰';
      case RewardCategory.timeOff:
        return '🏖️';
      case RewardCategory.gift:
        return '🎁';
      case RewardCategory.experience:
        return '🎭';
      case RewardCategory.recognition:
        return '🏆';
      case RewardCategory.other:
        return '📦';
    }
  }
}

/// Status da solicitação de resgate (1:1 com `RedemptionStatus` do backend).
enum RedemptionStatus {
  pending,
  approved,
  rejected,
  delivered,
  cancelled,
  unknown;

  static RedemptionStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'pending':
        return RedemptionStatus.pending;
      case 'approved':
        return RedemptionStatus.approved;
      case 'rejected':
        return RedemptionStatus.rejected;
      case 'delivered':
        return RedemptionStatus.delivered;
      case 'cancelled':
      case 'canceled':
        return RedemptionStatus.cancelled;
      default:
        return RedemptionStatus.unknown;
    }
  }

  /// Valor exato enviado à API (para filtro `status`).
  String get raw {
    switch (this) {
      case RedemptionStatus.pending:
        return 'pending';
      case RedemptionStatus.approved:
        return 'approved';
      case RedemptionStatus.rejected:
        return 'rejected';
      case RedemptionStatus.delivered:
        return 'delivered';
      case RedemptionStatus.cancelled:
        return 'cancelled';
      case RedemptionStatus.unknown:
        return '';
    }
  }

  String get label {
    switch (this) {
      case RedemptionStatus.pending:
        return 'Aguardando aprovação';
      case RedemptionStatus.approved:
        return 'Aprovado';
      case RedemptionStatus.rejected:
        return 'Rejeitado';
      case RedemptionStatus.delivered:
        return 'Entregue';
      case RedemptionStatus.cancelled:
        return 'Cancelado';
      case RedemptionStatus.unknown:
        return 'Resgate';
    }
  }

  /// Rótulo curto (pills/abas).
  String get shortLabel {
    switch (this) {
      case RedemptionStatus.pending:
        return 'Pendente';
      default:
        return label;
    }
  }
}

/// Prêmio do catálogo — espelha `Reward` do web.
class Reward {
  final String id;
  final String name;
  final String? description;
  final RewardCategory category;
  final int pointsCost;
  final double? monetaryValue;
  final String? imageUrl;
  final String? icon;
  final int? stockQuantity; // null = estoque ilimitado
  final int redeemedCount;
  final bool isActive;
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Reward({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    required this.pointsCost,
    this.monetaryValue,
    this.imageUrl,
    this.icon,
    this.stockQuantity,
    required this.redeemedCount,
    required this.isActive,
    required this.displayOrder,
    this.createdAt,
    this.updatedAt,
  });

  /// Emoji exibido no card (o do prêmio ou o padrão da categoria).
  String get displayIcon {
    final i = (icon ?? '').trim();
    return i.isNotEmpty ? i : category.defaultIcon;
  }

  /// `true` se ainda há unidades (ou estoque ilimitado). Paridade `hasStock`.
  bool get hasStock {
    if (stockQuantity == null) return true;
    return redeemedCount < stockQuantity!;
  }

  /// Unidades restantes (null = ilimitado). Paridade `getAvailableStock`.
  int? get availableStock {
    if (stockQuantity == null) return null;
    final left = stockQuantity! - redeemedCount;
    return left > 0 ? left : 0;
  }

  /// Pontos que faltam para o usuário alcançar este prêmio.
  int pointsNeeded(int myPoints) {
    final needed = pointsCost - myPoints;
    return needed > 0 ? needed : 0;
  }

  bool canAfford(int myPoints) => myPoints >= pointsCost;

  factory Reward.fromJson(Map<String, dynamic> json) {
    return Reward(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      category: RewardCategory.fromRaw(json['category']?.toString()),
      pointsCost: _toInt(json['pointsCost'] ?? json['points_cost']),
      monetaryValue:
          _toDoubleOrNull(json['monetaryValue'] ?? json['monetary_value']),
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString(),
      icon: json['icon']?.toString(),
      stockQuantity:
          _toIntOrNull(json['stockQuantity'] ?? json['stock_quantity']),
      redeemedCount: _toInt(json['redeemedCount'] ?? json['redeemed_count']),
      isActive: _toBool(json['isActive'] ?? json['is_active'], true),
      displayOrder: _toInt(json['displayOrder'] ?? json['display_order']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Solicitação de resgate — espelha `RewardRedemption` do web (com relations
/// desnormalizadas: reward, user, reviewedBy, deliveredBy).
class RewardRedemption {
  final String id;
  final String userId;
  final String rewardId;
  final RedemptionStatus status;
  final int pointsSpent;
  final String? userNotes;
  final DateTime? reviewedAt;
  final String? reviewNotes;
  final DateTime? deliveredAt;
  final DateTime? createdAt;

  final Reward? reward;
  final String? userName;
  final String? userEmail;
  final String? userAvatarUrl;
  final String? reviewedByName;
  final String? deliveredByName;

  const RewardRedemption({
    required this.id,
    required this.userId,
    required this.rewardId,
    required this.status,
    required this.pointsSpent,
    this.userNotes,
    this.reviewedAt,
    this.reviewNotes,
    this.deliveredAt,
    this.createdAt,
    this.reward,
    this.userName,
    this.userEmail,
    this.userAvatarUrl,
    this.reviewedByName,
    this.deliveredByName,
  });

  String get rewardName {
    final n = reward?.name.trim() ?? '';
    return n.isNotEmpty ? n : 'Prêmio';
  }

  String get displayIcon => reward?.displayIcon ?? '🎁';

  bool get isPending => status == RedemptionStatus.pending;
  bool get canReview => status == RedemptionStatus.pending;
  bool get canDeliver => status == RedemptionStatus.approved;

  factory RewardRedemption.fromJson(Map<String, dynamic> json) {
    final reward = _toMap(json['reward']);
    final user = _toMap(json['user']);
    final reviewedBy = _toMap(json['reviewedBy'] ?? json['reviewed_by']);
    final deliveredBy = _toMap(json['deliveredBy'] ?? json['delivered_by']);

    return RewardRedemption(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      rewardId:
          json['rewardId']?.toString() ?? json['reward_id']?.toString() ?? '',
      status: RedemptionStatus.fromRaw(json['status']?.toString()),
      pointsSpent: _toInt(json['pointsSpent'] ?? json['points_spent']),
      userNotes: json['userNotes']?.toString() ?? json['user_notes']?.toString(),
      reviewedAt: _toDate(json['reviewedAt'] ?? json['reviewed_at']),
      reviewNotes:
          json['reviewNotes']?.toString() ?? json['review_notes']?.toString(),
      deliveredAt: _toDate(json['deliveredAt'] ?? json['delivered_at']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      reward: reward != null ? Reward.fromJson(reward) : null,
      userName: user?['name']?.toString(),
      userEmail: user?['email']?.toString(),
      userAvatarUrl: user?['profileImageUrl']?.toString() ??
          user?['profile_image_url']?.toString(),
      reviewedByName: reviewedBy?['name']?.toString(),
      deliveredByName: deliveredBy?['name']?.toString(),
    );
  }
}

/// Resposta de `GET /rewards/redemptions/pending` (lista + total).
class RedemptionListResult {
  final List<RewardRedemption> redemptions;
  final int total;

  const RedemptionListResult({required this.redemptions, required this.total});

  static const empty = RedemptionListResult(redemptions: [], total: 0);
}

/// Resposta de `GET /rewards/stats/redemptions`.
class RewardStats {
  final int pending;
  final int approved;
  final int rejected;
  final int delivered;
  final int total;
  final int totalPointsSpent;

  const RewardStats({
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.delivered,
    required this.total,
    required this.totalPointsSpent,
  });

  static const zero = RewardStats(
    pending: 0,
    approved: 0,
    rejected: 0,
    delivered: 0,
    total: 0,
    totalPointsSpent: 0,
  );

  factory RewardStats.fromJson(Map<String, dynamic> json) {
    return RewardStats(
      pending: _toInt(json['pending']),
      approved: _toInt(json['approved']),
      rejected: _toInt(json['rejected']),
      delivered: _toInt(json['delivered']),
      total: _toInt(json['total']),
      totalPointsSpent:
          _toInt(json['totalPointsSpent'] ?? json['total_points_spent']),
    );
  }
}

/// Payload de criação/edição de prêmio (paridade `CreateRewardRequest` /
/// `UpdateRewardRequest` do web). Campos null são omitidos do JSON.
class RewardPayload {
  final String name;
  final String? description;
  final RewardCategory category;
  final int pointsCost;
  final double? monetaryValue;
  final String? icon;
  final int? stockQuantity;
  final int? displayOrder;
  final bool? isActive; // só na edição

  const RewardPayload({
    required this.name,
    this.description,
    required this.category,
    required this.pointsCost,
    this.monetaryValue,
    this.icon,
    this.stockQuantity,
    this.displayOrder,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'name': name,
      'category': category.raw,
      'pointsCost': pointsCost,
    };
    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) out['description'] = desc;
    if (monetaryValue != null && monetaryValue! > 0) {
      out['monetaryValue'] = monetaryValue;
    }
    final ic = icon?.trim();
    if (ic != null && ic.isNotEmpty) out['icon'] = ic;
    if (stockQuantity != null && stockQuantity! > 0) {
      out['stockQuantity'] = stockQuantity;
    }
    if (displayOrder != null) out['displayOrder'] = displayOrder;
    if (isActive != null) out['isActive'] = isActive;
    return out;
  }
}
