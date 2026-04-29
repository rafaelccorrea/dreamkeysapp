import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'secure_storage_service.dart';
import '../utils/jwt_utils.dart';

/// Serviço para refresh periódico de tokens em background
class TokenRefreshService {
  TokenRefreshService._();

  static final TokenRefreshService instance = TokenRefreshService._();
  
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  /// Inicia o serviço de refresh periódico
  /// Verifica a cada 1 dia se o token expira em menos de 3 minutos
  void startPeriodicRefresh() {
    // Limpar timer anterior se existir
    stopPeriodicRefresh();

    debugPrint('🔄 [TOKEN_REFRESH] Iniciando refresh periódico...');

    // Verificar imediatamente
    _checkAndRefreshToken();

    // Verificar a cada 1 dia (24 horas)
    _refreshTimer = Timer.periodic(
      const Duration(days: 1),
      (_) => _checkAndRefreshToken(),
    );
  }

  /// Para o serviço de refresh periódico
  void stopPeriodicRefresh() {
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
      _refreshTimer = null;
      debugPrint('⏹️ [TOKEN_REFRESH] Refresh periódico parado');
    }
  }

  /// Verifica se o token expira em menos de 3 minutos e faz refresh se necessário
  Future<void> _checkAndRefreshToken() async {
    if (_isRefreshing) {
      debugPrint('⏳ [TOKEN_REFRESH] Refresh já em andamento, ignorando...');
      return;
    }

    try {
      final token = await SecureStorageService.instance.getAccessToken();
      
      if (token == null || token.isEmpty) {
        debugPrint('ℹ️ [TOKEN_REFRESH] Nenhum token encontrado');
        return;
      }

      // Verificar se token é válido
      if (!JwtUtils.isTokenValid(token)) {
        debugPrint('⚠️ [TOKEN_REFRESH] Token já expirado');
        return;
      }

      // Verificar se expira em menos de 3 minutos
      final timeUntilExpiry = JwtUtils.getTimeUntilExpiry(token);
      
      if (timeUntilExpiry == null) {
        debugPrint('⚠️ [TOKEN_REFRESH] Não foi possível calcular tempo de expiração');
        return;
      }

      // Se expira em menos de 3 minutos (180 segundos) e ainda não expirou
      if (timeUntilExpiry < 180 && timeUntilExpiry > 0) {
        debugPrint(
          '🔄 [TOKEN_REFRESH] Token expira em ${timeUntilExpiry}s, fazendo refresh proativo...',
        );

        _isRefreshing = true;

        try {
          final authService = AuthService.instance;
          final refreshResponse = await authService.refreshToken();

          if (refreshResponse.success && refreshResponse.data != null) {
            debugPrint('✅ [TOKEN_REFRESH] Token renovado com sucesso em background');
          } else {
            debugPrint('❌ [TOKEN_REFRESH] Falha ao renovar token: ${refreshResponse.message}');
          }
        } catch (e) {
          debugPrint('❌ [TOKEN_REFRESH] Erro ao renovar token: $e');
        } finally {
          _isRefreshing = false;
        }
      } else {
        final minutesUntilExpiry = (timeUntilExpiry / 60).toStringAsFixed(1);
        debugPrint(
          'ℹ️ [TOKEN_REFRESH] Token ainda válido por $minutesUntilExpiry minutos, não é necessário refresh',
        );
      }
    } catch (e) {
      debugPrint('❌ [TOKEN_REFRESH] Erro ao verificar token: $e');
    }
  }

  /// Força um refresh manual do token
  Future<bool> performManualRefresh() async {
    if (_isRefreshing) {
      debugPrint('⏳ [TOKEN_REFRESH] Refresh já em andamento');
      return false;
    }

    _isRefreshing = true;
    try {
      final authService = AuthService.instance;
      final refreshResponse = await authService.refreshToken();

      if (refreshResponse.success && refreshResponse.data != null) {
        debugPrint('✅ [TOKEN_REFRESH] Refresh manual bem-sucedido');
        return true;
      } else {
        debugPrint('❌ [TOKEN_REFRESH] Falha no refresh manual: ${refreshResponse.message}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [TOKEN_REFRESH] Erro no refresh manual: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Verifica se o serviço está ativo
  bool get isActive => _refreshTimer != null && _refreshTimer!.isActive;
}

