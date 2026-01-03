import 'package:flutter/foundation.dart';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Modelo de Subscription
class Subscription {
  final String id;
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  Subscription({
    required this.id,
    required this.status,
    this.expiresAt,
    this.createdAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}

/// Modelo de SubscriptionAccessInfo
class SubscriptionAccessInfo {
  final bool hasAccess;
  final String status; // 'active' | 'expired' | 'suspended' | 'none'
  final String? reason;
  final bool canAccessFeatures;
  final bool isExpired;
  final bool isSuspended;
  final Subscription? subscription;
  final int? daysUntilExpiry;

  SubscriptionAccessInfo({
    required this.hasAccess,
    required this.status,
    this.reason,
    required this.canAccessFeatures,
    required this.isExpired,
    required this.isSuspended,
    this.subscription,
    this.daysUntilExpiry,
  });

  factory SubscriptionAccessInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionAccessInfo(
      hasAccess: json['hasAccess'] as bool? ?? false,
      status: json['status']?.toString() ?? 'none',
      reason: json['reason']?.toString(),
      canAccessFeatures: json['canAccessFeatures'] as bool? ?? false,
      isExpired: json['isExpired'] as bool? ?? false,
      isSuspended: json['isSuspended'] as bool? ?? false,
      subscription: json['subscription'] != null
          ? Subscription.fromJson(json['subscription'] as Map<String, dynamic>)
          : null,
      daysUntilExpiry: json['daysUntilExpiry'] as int?,
    );
  }
}

/// Serviço para gerenciar assinaturas
class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();
  final ApiService _apiService = ApiService.instance;

  /// Verifica acesso à assinatura
  Future<ApiResponse<SubscriptionAccessInfo>> checkSubscriptionAccess() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.checkSubscriptionAccess,
      );

      if (response.success && response.data != null) {
        final accessInfo = SubscriptionAccessInfo.fromJson(response.data!);
        debugPrint('✅ [SUBSCRIPTION_SERVICE] Acesso verificado: ${accessInfo.hasAccess}');
        return ApiResponse.success(
          data: accessInfo,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar acesso à assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [SUBSCRIPTION_SERVICE] Erro ao verificar acesso: $e');
      debugPrint('📚 [SUBSCRIPTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao verificar acesso à assinatura: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}












