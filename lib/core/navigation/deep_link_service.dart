import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../routes/app_routes.dart';
import '../session/session_bootstrap.dart';
import 'app_navigator.dart';

/// Deep links `dreamkeys://` (hoje: Ilha Dinâmica do check-in).
///
/// Fiação:
///  - iOS captura a URL no `AppDelegate` (cold start via `launchOptions`,
///    warm start via `application(_:open:options:)`) e entrega por este
///    MethodChannel — o roteamento default do engine foi desligado no
///    Info.plist porque empurrava o path cru pro Navigator ("Página não
///    encontrada").
///  - `init()` roda no boot: registra o handler (warm) e puxa o link
///    inicial (cold).
///  - Um link que chega antes do usuário alcançar a Home (splash/login em
///    andamento) fica PENDENTE e é disparado por [notifyHomeReady], chamado
///    pela DashboardPage — check-in exige sessão, então navegar antes disso
///    quebraria o fluxo de auth.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const MethodChannel _channel =
      MethodChannel('com.dreamkeys.corretor/deep_link');

  String? _pending;
  bool _homeReady = false;

  // Cold start pode entregar o MESMO link duas vezes (onLink dispara sem
  // handler + getInitialLink devolve o pendente). Janela curta de dedupe.
  String? _lastHandled;
  DateTime? _lastHandledAt;

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          _handle(link);
        }
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) {
        _handle(initial);
      }
    } on MissingPluginException {
      // Plataforma sem o canal (Android/desktop) — deep link é só iOS hoje.
    } on PlatformException catch (e) {
      debugPrint('🔗 [DEEPLINK] getInitialLink falhou: ${e.message}');
    }
  }

  /// Chamado pela Home (DashboardPage) quando o usuário autenticado chega lá.
  /// Consome o link pendente do cold start e libera navegação imediata para
  /// links futuros (warm start).
  void notifyHomeReady() {
    _homeReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      unawaited(_navigate(pending));
    }
  }

  void _handle(String link) {
    final now = DateTime.now();
    if (link == _lastHandled &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 3)) {
      return; // dupla entrega do mesmo tap
    }
    _lastHandled = link;
    _lastHandledAt = now;

    if (!_homeReady || appNavigatorKey.currentState == null) {
      _pending = link; // cold start: espera a Home montar
      return;
    }
    unawaited(_navigate(link));
  }

  Future<void> _navigate(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'dreamkeys') return;

    // Em scheme custom o 1º segmento é o HOST: dreamkeys://check-in/checkout
    // → host "check-in", path "/checkout".
    final segments = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (segments.isEmpty) return;

    // O check-in é rota PROTEGIDA (exige `X-Company-ID`). A fila do
    // `_homeReady` garante que o usuário já está autenticado, mas não que a
    // empresa foi resolvida — este gate garante. Idempotente: retorna na
    // hora quando a sessão já está pronta.
    await SessionBootstrap.instance.ensureReady(
      timeout: const Duration(seconds: 12),
    );

    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      _pending = link;
      return;
    }

    switch (segments.first) {
      case 'check-in':
        final wantsCheckout = segments.length > 1 && segments[1] == 'checkout';
        nav.pushNamed(
          AppRoutes.checkIn,
          arguments: <String, dynamic>{'checkout': wantsCheckout},
        );
        break;
      default:
        debugPrint('🔗 [DEEPLINK] destino desconhecido: $link');
    }
  }
}
