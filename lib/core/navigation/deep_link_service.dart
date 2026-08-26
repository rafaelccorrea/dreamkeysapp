import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../shared/services/secure_storage_service.dart';
import '../../shared/utils/app_deep_link.dart';
import '../routes/app_routes.dart';
import '../session/session_bootstrap.dart';
import 'app_navigator.dart';

/// Deep links do app: esquema próprio `dreamkeys://` (Ilha Dinâmica do
/// check-in) e links https do sistema (Universal Links no iOS / App Links no
/// Android) — `https://intellisysbr.com/sistema/...`, o mesmo domínio dos
/// e-mails do backend (FRONTEND_URL/APP_URL).
///
/// Fiação:
///  - iOS captura a URL no `AppDelegate` (cold start via `launchOptions`,
///    warm start via `application(_:open:options:)` para o esquema próprio e
///    `application(_:continue:restorationHandler:)` para os Universal Links) e
///    entrega por este MethodChannel — o roteamento default do engine foi
///    desligado no Info.plist porque empurrava o path cru pro Navigator
///    ("Página não encontrada").
///  - Android faz o mesmo pela `MainActivity.kt` (`getIntent()` no cold start,
///    `onNewIntent` no warm), com os intent-filters do AndroidManifest.
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

  /// Hosts cujos links https pertencem ao app. É o domínio do SPA do sistema
  /// (`intellisysbr.com`) — `www` entra só porque um redirect/entrada manual
  /// pode chegar assim. NÃO inclui `imobiliariauniao.com.br` (site público de
  /// imóveis, outro projeto) nem `dreamkeys.com` (institucional): esses não
  /// têm tela no app e devem continuar abrindo no navegador.
  static const Set<String> _appHosts = <String>{
    'intellisysbr.com',
    'www.intellisysbr.com',
  };

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
      // Plataforma sem o canal nativo (desktop/testes). iOS e Android
      // implementam; aqui é só não quebrar o boot.
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
    if (uri == null) return;

    final isCustomScheme = uri.scheme == 'dreamkeys';
    // Universal Link / App Link: só do domínio do sistema. O intent-filter e
    // o AASA já filtram na plataforma, mas o guard aqui vale para o link que
    // chega por outro caminho (ex.: `onNewIntent` de um share).
    final isWebLink = (uri.scheme == 'https' || uri.scheme == 'http') &&
        _appHosts.contains(uri.host.toLowerCase());
    if (!isCustomScheme && !isWebLink) return;

    // Em scheme custom o 1º segmento é o HOST: dreamkeys://check-in/checkout
    // → host "check-in", path "/checkout".
    final segments = isCustomScheme
        ? <String>[
            if (uri.host.isNotEmpty) uri.host,
            ...uri.pathSegments.where((s) => s.isNotEmpty),
          ]
        : const <String>[];
    if (isCustomScheme && segments.isEmpty) return;

    // DESLOGADO: `_homeReady` é estado deste singleton e SOBREVIVE ao logout
    // (o `AuthService.logout` só reseta o `SessionBootstrap`). Sem este guard,
    // um link de e-mail tocado com o app na tela de login empurrava uma rota
    // PROTEGIDA por cima dela — a tela subia sem token e morria em 401/
    // "Company ID não encontrado". Antes dos links https isso quase não
    // acontecia (o único deep link vinha da Ilha Dinâmica, que só existe
    // logado); agora qualquer e-mail é porta de entrada.
    // Guardamos o link e RE-FECHAMOS a comporta: a DashboardPage chama
    // `notifyHomeReady()` no initState de novo depois do login e o link sai.
    final token = await SecureStorageService.instance.getAccessToken();
    if (token == null || token.isEmpty) {
      _pending = link;
      _homeReady = false;
      return;
    }

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

    if (isWebLink) {
      // Reusa o tradutor URL→rota que já existe (mesma whitelist do push e da
      // lista de notificações): ele aceita URL absoluta, tira o prefixo
      // `/sistema` e cobre kanban, agenda, imóveis, clientes, fichas,
      // vistorias, documentos, checklists… Nada de regra duplicada aqui.
      final route = AppDeepLink.resolve(actionUrl: link);
      if (route != null && route.isNotEmpty) {
        if (route == AppRoutes.home) {
          // `/sistema/dashboard` resolve para a Home. Empilhar a Home EM CIMA
          // da Home é o bug do botão voltar virar esteira (5 links = 5 Homes).
          // Aqui o destino é literalmente "volte ao início", então limpamos —
          // mesmo padrão do fallback do `AppPushService`.
          nav.pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
          return;
        }
        nav.pushNamed(route);
        return;
      }
      // Caminho sem tela no app (financeiro, /login, /reset-password…): NÃO
      // navegamos nem limpamos a pilha. O AASA/intent-filter já recorta os
      // paths, então isso é caso de borda; empurrar a Home aqui arrancaria a
      // tela em que o usuário estava. O cold start já cai na Home por si.
      debugPrint('🔗 [DEEPLINK] link https sem tela no app: $link');
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
