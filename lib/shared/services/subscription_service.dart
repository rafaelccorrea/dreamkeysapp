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

  /// `false` quando o dado NÃO veio do servidor nesta chamada (falha de
  /// transporte). Nesse caso o acesso é otimista e deve ser reavaliado — nunca
  /// use para bloquear a conta.
  final bool isAuthoritative;

  SubscriptionAccessInfo({
    required this.hasAccess,
    required this.status,
    this.reason,
    required this.canAccessFeatures,
    required this.isExpired,
    required this.isSuspended,
    this.subscription,
    this.daysUntilExpiry,
    this.isAuthoritative = true,
  });

  /// Estado usado quando o servidor não respondeu e não há estado anterior
  /// conhecido: libera o acesso e marca como não autoritativo.
  factory SubscriptionAccessInfo.unknown() {
    return SubscriptionAccessInfo(
      hasAccess: true,
      status: 'unknown',
      reason: 'Não foi possível verificar a assinatura agora',
      canAccessFeatures: true,
      isExpired: false,
      isSuspended: false,
      isAuthoritative: false,
    );
  }

  SubscriptionAccessInfo asStale() {
    return SubscriptionAccessInfo(
      hasAccess: hasAccess,
      status: status,
      reason: reason,
      canAccessFeatures: canAccessFeatures,
      isExpired: isExpired,
      isSuspended: isSuspended,
      subscription: subscription,
      daysUntilExpiry: daysUntilExpiry,
      isAuthoritative: false,
    );
  }

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

  /// Último estado confirmado pelo servidor, para sobreviver a uma queda.
  SubscriptionAccessInfo? _lastKnownAccess;

  /// Falha de transporte — rede, timeout, rate limit ou erro do servidor.
  /// Não é resposta sobre a assinatura, então NÃO pode bloquear a conta.
  static bool isTransportFailure(int statusCode) {
    return statusCode == 0 ||
        statusCode == 408 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  /// Descarta o estado em cache — chamar no logout/troca de conta para não
  /// levar a assinatura de uma conta para a seguinte.
  void clearCache() {
    _lastKnownAccess = null;
  }

  /// Verifica acesso à assinatura.
  ///
  /// Nunca devolve erro por falha de transporte: cai no último estado conhecido
  /// ou, se não houver, num acesso otimista (`isAuthoritative == false`). Tratar
  /// 5xx/timeout como "sem assinatura" foi o que prendeu corretores na tela
  /// "Sistema suspenso" durante o crash-loop do backend em 22–24/07.
  Future<ApiResponse<SubscriptionAccessInfo>> checkSubscriptionAccess() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.checkSubscriptionAccess,
      );

      if (response.success && response.data != null) {
        final accessInfo = SubscriptionAccessInfo.fromJson(response.data!);
        _lastKnownAccess = accessInfo;
        debugPrint('✅ [SUBSCRIPTION_SERVICE] Acesso verificado: ${accessInfo.hasAccess}');
        return ApiResponse.success(
          data: accessInfo,
          statusCode: response.statusCode,
        );
      }

      if (isTransportFailure(response.statusCode)) {
        return _fallbackAccess(response.statusCode, response.message);
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar acesso à assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [SUBSCRIPTION_SERVICE] Erro ao verificar acesso: $e');
      debugPrint('📚 [SUBSCRIPTION_SERVICE] StackTrace: $stackTrace');
      return _fallbackAccess(0, e.toString());
    }
  }

  ApiResponse<SubscriptionAccessInfo> _fallbackAccess(
    int statusCode,
    String? detail,
  ) {
    final fallback = _lastKnownAccess?.asStale() ?? SubscriptionAccessInfo.unknown();
    debugPrint(
      '⚠️ [SUBSCRIPTION_SERVICE] Falha de transporte ($statusCode) ao verificar '
      'assinatura — mantendo acesso ${_lastKnownAccess != null ? 'do último estado conhecido' : 'otimista'}. Detalhe: $detail',
    );
    return ApiResponse.success(data: fallback, statusCode: statusCode);
  }
}












