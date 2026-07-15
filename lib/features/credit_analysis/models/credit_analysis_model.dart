// Modelos do módulo de Análise de Crédito — espelham `credit-analysis.entity.ts`
// e as respostas de `GET /credit-analysis`, `GET /credit-analysis/statistics` e
// `GET /credit-analysis/settings` do backend (paridade com
// `creditAnalysisService.ts` / `creditAnalysisSettingsService.ts` do imobx-front).

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

bool _toBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'sim';
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Status da análise (1:1 com o backend — `PENDING`, `PROCESSING`,
/// `APPROVED`, `REJECTED`, `COMPLETED`, `ERROR`, `FAILED`, `MANUAL_REVIEW`).
enum CreditAnalysisStatus {
  pending,
  processing,
  approved,
  rejected,
  completed,
  error,
  failed,
  manualReview,
  unknown;

  static CreditAnalysisStatus fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PENDING':
        return CreditAnalysisStatus.pending;
      case 'PROCESSING':
        return CreditAnalysisStatus.processing;
      case 'APPROVED':
        return CreditAnalysisStatus.approved;
      case 'REJECTED':
        return CreditAnalysisStatus.rejected;
      case 'COMPLETED':
        return CreditAnalysisStatus.completed;
      case 'ERROR':
        return CreditAnalysisStatus.error;
      case 'FAILED':
        return CreditAnalysisStatus.failed;
      case 'MANUAL_REVIEW':
        return CreditAnalysisStatus.manualReview;
      default:
        return CreditAnalysisStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case CreditAnalysisStatus.pending:
        return 'Pendente';
      case CreditAnalysisStatus.processing:
        return 'Processando';
      case CreditAnalysisStatus.approved:
        return 'Aprovado';
      case CreditAnalysisStatus.rejected:
        return 'Reprovado';
      case CreditAnalysisStatus.completed:
        return 'Concluída';
      case CreditAnalysisStatus.error:
        return 'Erro na consulta';
      case CreditAnalysisStatus.failed:
        return 'Falhou';
      case CreditAnalysisStatus.manualReview:
        return 'Revisão manual';
      case CreditAnalysisStatus.unknown:
        return 'Análise';
    }
  }

  bool get isError =>
      this == CreditAnalysisStatus.error || this == CreditAnalysisStatus.failed;
}

/// Nível de risco calculado pela consulta.
enum CreditRiskLevel {
  veryLow,
  low,
  medium,
  high,
  veryHigh,
  unknown;

  static CreditRiskLevel fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'VERY_LOW':
        return CreditRiskLevel.veryLow;
      case 'LOW':
        return CreditRiskLevel.low;
      case 'MEDIUM':
        return CreditRiskLevel.medium;
      case 'HIGH':
        return CreditRiskLevel.high;
      case 'VERY_HIGH':
        return CreditRiskLevel.veryHigh;
      default:
        return CreditRiskLevel.unknown;
    }
  }

  String get label {
    switch (this) {
      case CreditRiskLevel.veryLow:
        return 'Muito baixo';
      case CreditRiskLevel.low:
        return 'Baixo';
      case CreditRiskLevel.medium:
        return 'Médio';
      case CreditRiskLevel.high:
        return 'Alto';
      case CreditRiskLevel.veryHigh:
        return 'Muito alto';
      case CreditRiskLevel.unknown:
        return '—';
    }
  }
}

/// Recomendação do parecer automático.
enum CreditRecommendation {
  approve,
  reject,
  manualReview,
  unknown;

  static CreditRecommendation fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'APPROVE':
        return CreditRecommendation.approve;
      case 'REJECT':
        return CreditRecommendation.reject;
      case 'MANUAL_REVIEW':
        return CreditRecommendation.manualReview;
      default:
        return CreditRecommendation.unknown;
    }
  }

  String get label {
    switch (this) {
      case CreditRecommendation.approve:
        return 'Aprovar';
      case CreditRecommendation.reject:
        return 'Rejeitar';
      case CreditRecommendation.manualReview:
        return 'Revisar manualmente';
      case CreditRecommendation.unknown:
        return '—';
    }
  }
}

/// Aluguel vinculado à análise (quando existir).
class CreditAnalysisRental {
  final String id;
  final String? tenantName;
  final String? tenantDocument;
  final double? monthlyValue;
  final String? status;
  final String? propertyAddress;
  final String? propertyTitle;

  const CreditAnalysisRental({
    required this.id,
    this.tenantName,
    this.tenantDocument,
    this.monthlyValue,
    this.status,
    this.propertyAddress,
    this.propertyTitle,
  });

  String get label {
    final name = (tenantName ?? '').trim();
    if (name.isNotEmpty) return name;
    final prop = (propertyTitle ?? propertyAddress ?? '').trim();
    if (prop.isNotEmpty) return prop;
    return id;
  }

  factory CreditAnalysisRental.fromJson(Map<String, dynamic> json) {
    final property = json['property'] is Map
        ? Map<String, dynamic>.from(json['property'] as Map)
        : null;
    return CreditAnalysisRental(
      id: json['id']?.toString() ?? '',
      tenantName: json['tenantName']?.toString(),
      tenantDocument: json['tenantDocument']?.toString(),
      monthlyValue:
          json['monthlyValue'] == null ? null : _toDouble(json['monthlyValue']),
      status: json['status']?.toString(),
      propertyAddress: property?['address']?.toString(),
      propertyTitle: property?['title']?.toString(),
    );
  }
}

/// Uma análise de crédito (parecer completo da consulta Serasa).
class CreditAnalysis {
  final String id;
  final String analyzedCpf;
  final String? analyzedName;
  final String? provider;
  final CreditAnalysisStatus status;
  final int creditScore;
  final CreditRiskLevel riskLevel;
  final bool hasRestrictions;
  final int restrictionsCount;
  final double totalDebt;
  final bool hasLawsuits;
  final int lawsuitsCount;
  final bool hasProtests;
  final int protestsCount;
  final CreditRecommendation recommendation;
  final String? notes;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Mensagem amigável quando `status == ERROR` (ex.: CPF não encontrado).
  final String? errorMessage;
  final String? rentalId;
  final CreditAnalysisRental? rental;

  const CreditAnalysis({
    required this.id,
    required this.analyzedCpf,
    this.analyzedName,
    this.provider,
    required this.status,
    required this.creditScore,
    required this.riskLevel,
    required this.hasRestrictions,
    required this.restrictionsCount,
    required this.totalDebt,
    required this.hasLawsuits,
    required this.lawsuitsCount,
    required this.hasProtests,
    required this.protestsCount,
    required this.recommendation,
    this.notes,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
    this.errorMessage,
    this.rentalId,
    this.rental,
  });

  /// Score ≥ 700 é considerado bom (mesma régua do web).
  bool get hasGoodScore => creditScore >= 700;

  /// Refazer análise: só após 15 dias da última (regra espelhada do web).
  bool get canRedo {
    final created = createdAt;
    if (created == null) return true;
    return DateTime.now().difference(created).inDays >= 15;
  }

  factory CreditAnalysis.fromJson(Map<String, dynamic> json) {
    final rentalRaw = json['rental'];
    return CreditAnalysis(
      id: json['id']?.toString() ?? '',
      analyzedCpf:
          (json['analyzedCpf'] ?? json['analyzed_cpf'])?.toString() ?? '',
      analyzedName:
          (json['analyzedName'] ?? json['analyzed_name'])?.toString(),
      provider: json['provider']?.toString(),
      status: CreditAnalysisStatus.fromRaw(json['status']?.toString()),
      creditScore: _toInt(json['creditScore'] ?? json['credit_score']),
      riskLevel: CreditRiskLevel.fromRaw(
          (json['riskLevel'] ?? json['risk_level'])?.toString()),
      hasRestrictions:
          _toBool(json['hasRestrictions'] ?? json['has_restrictions']),
      restrictionsCount:
          _toInt(json['restrictionsCount'] ?? json['restrictions_count']),
      totalDebt: _toDouble(json['totalDebt'] ?? json['total_debt']),
      hasLawsuits: _toBool(json['hasLawsuits'] ?? json['has_lawsuits']),
      lawsuitsCount: _toInt(json['lawsuitsCount'] ?? json['lawsuits_count']),
      hasProtests: _toBool(json['hasProtests'] ?? json['has_protests']),
      protestsCount: _toInt(json['protestsCount'] ?? json['protests_count']),
      recommendation:
          CreditRecommendation.fromRaw(json['recommendation']?.toString()),
      notes: json['notes']?.toString(),
      reviewedBy: json['reviewedBy']?.toString(),
      reviewedAt: _toDate(json['reviewedAt'] ?? json['reviewed_at']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
      errorMessage:
          (json['errorMessage'] ?? json['error_message'])?.toString(),
      rentalId: json['rentalId']?.toString(),
      rental: rentalRaw is Map
          ? CreditAnalysisRental.fromJson(
              Map<String, dynamic>.from(rentalRaw))
          : null,
    );
  }
}

/// Resposta de `GET /credit-analysis/statistics`.
class CreditAnalysisStatistics {
  final int total;
  final int pending;
  final int processing;
  final int completed;
  final int failed;
  final int approved;
  final int rejected;
  final int manualReview;
  final double averageScore;

  /// Fração 0..1 (o web multiplica por 100 na exibição).
  final double approvalRate;

  const CreditAnalysisStatistics({
    required this.total,
    required this.pending,
    required this.processing,
    required this.completed,
    required this.failed,
    required this.approved,
    required this.rejected,
    required this.manualReview,
    required this.averageScore,
    required this.approvalRate,
  });

  static const zero = CreditAnalysisStatistics(
    total: 0,
    pending: 0,
    processing: 0,
    completed: 0,
    failed: 0,
    approved: 0,
    rejected: 0,
    manualReview: 0,
    averageScore: 0,
    approvalRate: 0,
  );

  factory CreditAnalysisStatistics.fromJson(Map<String, dynamic> json) {
    return CreditAnalysisStatistics(
      total: _toInt(json['total']),
      pending: _toInt(json['pending']),
      processing: _toInt(json['processing']),
      completed: _toInt(json['completed']),
      failed: _toInt(json['failed']),
      approved: _toInt(json['approved']),
      rejected: _toInt(json['rejected']),
      manualReview: _toInt(json['manualReview']),
      averageScore: _toDouble(json['averageScore']),
      approvalRate: _toDouble(json['approvalRate']),
    );
  }
}

/// Configurações (regras) de análise de crédito — exibidas SÓ LEITURA no app
/// (a edição fica no painel web). `GET /credit-analysis/settings`.
class CreditAnalysisSettings {
  // Aprovação automática
  final bool autoApproveEnabled;
  final int autoApproveMinScore;
  final int autoApproveMaxRestrictions;
  final double autoApproveMaxDebt;
  final bool autoApproveAllowLawsuits;
  final bool autoApproveAllowProtests;

  // Rejeição automática
  final bool autoRejectEnabled;
  final int autoRejectMaxScore;
  final int autoRejectMinRestrictions;
  final double autoRejectMinDebt;
  final bool autoRejectIfLawsuits;
  final bool autoRejectIfProtests;

  // Revisão manual
  final int manualReviewScoreMin;
  final int manualReviewScoreMax;
  final bool manualReviewIfRestrictions;
  final double manualReviewIfDebtAbove;

  // Outras regras
  final bool requireIncomeVerification;
  final double minIncomeRatio;

  // Regras para criação de aluguel
  final bool requireCreditAnalysisToCreateRental;
  final bool onlyAllowRentalIfAnalysisPositive;
  final int? minScoreToAllowRental;

  const CreditAnalysisSettings({
    required this.autoApproveEnabled,
    required this.autoApproveMinScore,
    required this.autoApproveMaxRestrictions,
    required this.autoApproveMaxDebt,
    required this.autoApproveAllowLawsuits,
    required this.autoApproveAllowProtests,
    required this.autoRejectEnabled,
    required this.autoRejectMaxScore,
    required this.autoRejectMinRestrictions,
    required this.autoRejectMinDebt,
    required this.autoRejectIfLawsuits,
    required this.autoRejectIfProtests,
    required this.manualReviewScoreMin,
    required this.manualReviewScoreMax,
    required this.manualReviewIfRestrictions,
    required this.manualReviewIfDebtAbove,
    required this.requireIncomeVerification,
    required this.minIncomeRatio,
    required this.requireCreditAnalysisToCreateRental,
    required this.onlyAllowRentalIfAnalysisPositive,
    this.minScoreToAllowRental,
  });

  factory CreditAnalysisSettings.fromJson(Map<String, dynamic> json) {
    return CreditAnalysisSettings(
      autoApproveEnabled: _toBool(json['autoApproveEnabled']),
      autoApproveMinScore: _toInt(json['autoApproveMinScore']),
      autoApproveMaxRestrictions: _toInt(json['autoApproveMaxRestrictions']),
      autoApproveMaxDebt: _toDouble(json['autoApproveMaxDebt']),
      autoApproveAllowLawsuits: _toBool(json['autoApproveAllowLawsuits']),
      autoApproveAllowProtests: _toBool(json['autoApproveAllowProtests']),
      autoRejectEnabled: _toBool(json['autoRejectEnabled']),
      autoRejectMaxScore: _toInt(json['autoRejectMaxScore']),
      autoRejectMinRestrictions: _toInt(json['autoRejectMinRestrictions']),
      autoRejectMinDebt: _toDouble(json['autoRejectMinDebt']),
      autoRejectIfLawsuits: _toBool(json['autoRejectIfLawsuits']),
      autoRejectIfProtests: _toBool(json['autoRejectIfProtests']),
      manualReviewScoreMin: _toInt(json['manualReviewScoreMin']),
      manualReviewScoreMax: _toInt(json['manualReviewScoreMax']),
      manualReviewIfRestrictions: _toBool(json['manualReviewIfRestrictions']),
      manualReviewIfDebtAbove: _toDouble(json['manualReviewIfDebtAbove']),
      requireIncomeVerification: _toBool(json['requireIncomeVerification']),
      minIncomeRatio: _toDouble(json['minIncomeRatio']),
      requireCreditAnalysisToCreateRental:
          _toBool(json['requireCreditAnalysisToCreateRental']),
      onlyAllowRentalIfAnalysisPositive:
          _toBool(json['onlyAllowRentalIfAnalysisPositive']),
      minScoreToAllowRental: json['minScoreToAllowRental'] == null
          ? null
          : _toInt(json['minScoreToAllowRental']),
    );
  }
}

/// Aba ativa da tela de análises.
enum CreditAnalysisTab { all, approved, review, rejected }
