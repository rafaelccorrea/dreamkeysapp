import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_service.dart';

/// Refresh de fundo do token (29/09/2026).
///
/// Antes checava a cada 1 DIA se o token vencia em menos de 3 minutos — com
/// JWT de ~15 min, na prática não havia refresh de fundo: app parado numa tela
/// deixava o token vencer, e os sockets reconectavam com token vencido
/// (`auth_error`) até alguém fazer uma requisição. Agora checa a cada 60 s,
/// no primeiro plano e ao voltar do segundo plano, e renova com margem de 3
/// minutos pela MESMA fila única do [ApiService] (nunca dois refreshes ao
/// mesmo tempo). Falha de rede não desloga — só a recusa do refresh token.
class TokenRefreshService with WidgetsBindingObserver {
  TokenRefreshService._();

  static final TokenRefreshService instance = TokenRefreshService._();

  static const Duration _intervalo = Duration(seconds: 60);
  static const int _margemSegundos = 180;

  Timer? _refreshTimer;
  bool _observando = false;
  bool _emPrimeiroPlano = true;

  /// Inicia o refresh de fundo (chamado no splash, depois do login).
  void startPeriodicRefresh() {
    stopPeriodicRefresh();
    if (!_observando) {
      _observando = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _emPrimeiroPlano = true;
    unawaited(_checar());
    _refreshTimer = Timer.periodic(_intervalo, (_) {
      if (_emPrimeiroPlano) unawaited(_checar());
    });
  }

  /// Para o refresh de fundo (logout).
  void stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _emPrimeiroPlano = state == AppLifecycleState.resumed;
    // Voltou do segundo plano: o token pode ter vencido lá.
    if (_emPrimeiroPlano && _refreshTimer != null) unawaited(_checar());
  }

  Future<void> _checar() async {
    try {
      await ApiService.instance.garantirTokenFresco(
        margemSegundos: _margemSegundos,
      );
    } catch (e) {
      debugPrint('⚠️ [TOKEN_REFRESH] Falha na checagem de fundo: $e');
    }
  }

  /// Força um refresh manual do token.
  Future<bool> performManualRefresh() async {
    final token = await ApiService.instance.garantirTokenFresco(
      margemSegundos: 1 << 30,
    );
    return token != null;
  }

  /// Verifica se o serviço está ativo
  bool get isActive => _refreshTimer != null && _refreshTimer!.isActive;
}
