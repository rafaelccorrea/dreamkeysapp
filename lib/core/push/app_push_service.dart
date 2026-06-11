import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import '../navigation/app_navigator.dart';
import '../routes/app_routes.dart';
import '../../shared/utils/app_deep_link.dart';
import '../../firebase_options.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/secure_storage_service.dart';

/// Identidade visual da notificação (espelha `AppColors.primary.primary`).
///
/// Mantemos hardcoded aqui para não importar a árvore de tema no isolate de
/// background (`firebaseMessagingBackgroundHandler` roda fora do widget tree).
const Color _brandRed = Color(0xFFD32F2F);

/// Ícone branco monocromático gerado em
/// `tools/generate_notification_icon.ps1` a partir de `ic_launcher_foreground`.
/// Android aplica o tint do canal/notification por cima — sem isto o sistema
/// renderiza um quadradinho branco genérico em vez do logo.
const String _smallIconResource = 'ic_notification';

const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  'imobx_alerts',
  'Alertas do sistema',
  description: 'Notificações do Intellisys (leads, tarefas, agenda…)',
  importance: Importance.high,
  ledColor: _brandRed,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _firebaseCoreReady = false;
bool _listenersAttached = false;
bool _localNotificationsReady = false;

/// Chave em [SharedPreferences] para garantir que a notificação de boas-vindas
/// seja exibida só uma vez por instalação (não em todo login/reabertura).
const String _welcomeShownPrefsKey = 'imobx_push_welcome_shown_v1';
bool _isDuplicateDefaultFirebaseAppError(Object error) {
  if (error is FirebaseException) {
    return error.code == 'duplicate-app';
  }
  final message = error.toString();
  return message.contains('[core/duplicate-app]') &&
      message.contains('already exists');
}

/// Inicialização mínima do plugin em isolate de background (sem tap handler).
Future<void> _ensureLocalNotificationsInBackground() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await _localNotifications.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
  );
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_pushChannel);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isFirebaseConfigured) {
    debugPrint(
      '📱 [PUSH] Background: Firebase não configurado (ignorando mensagem).',
    );
    return;
  }
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    if (_isDuplicateDefaultFirebaseAppError(e)) {
      // Em hot-restart/reanexo de isolate o app default pode já existir.
      debugPrint('📱 [PUSH] Background Firebase já inicializado (duplicate-app).');
    } else {
      debugPrint('📱 [PUSH] Background Firebase init: $e');
      return;
    }
  }

  debugPrint(
    '📱 [PUSH] Background FCM: messageId=${message.messageId} '
    'hasNotification=${message.notification != null}',
  );

  // Com payload `notification`, o Android mostra o alerta do sistema —
  // não duplicar com notificação local.
  if (!Platform.isAndroid) {
    return;
  }
  if (message.notification != null) {
    return;
  }

  final title = message.data['title'] ?? '';
  final body = message.data['body'] ?? '';
  if (title.isEmpty && body.isEmpty) {
    return;
  }

  try {
    await _ensureLocalNotificationsInBackground();
    final resolvedTitle = title.isEmpty ? 'Intellisys' : title;
    final resolvedBody =
        body.isEmpty ? 'Abra o app para ver a notificação.' : body;
    await _localNotifications.show(
      id: message.messageId?.hashCode.abs() ??
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: resolvedTitle,
      body: resolvedBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _pushChannel.id,
          _pushChannel.name,
          channelDescription: _pushChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIconResource,
          color: _brandRed,
          colorized: false,
          // BigText permite o usuário expandir mensagens longas sem truncar
          // — hábito que o usuário pega do WhatsApp/Insta/Slack.
          styleInformation: BigTextStyleInformation(
            resolvedBody,
            contentTitle: resolvedTitle,
            summaryText: 'Intellisys',
          ),
        ),
      ),
      payload: jsonEncode(message.data),
    );
  } catch (e) {
    debugPrint('📱 [PUSH] Background notificação local: $e');
  }
}

/// Push FCM + notificações locais (espelho das notificações do backend).
class AppPushService {
  AppPushService._();

  static final AppPushService instance = AppPushService._();

  /// Chamar uma vez no [main], antes do [runApp].
  /// O handler em background deve ser registado antes de [Firebase.initializeApp].
  static Future<void> setupFirebaseBeforeRunApp() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (!DefaultFirebaseOptions.isFirebaseConfigured) {
      _firebaseCoreReady = false;
      debugPrint(
        '📱 [PUSH] Firebase não configurado para esta plataforma (placeholders em '
        'lib/firebase_options.dart). Execute `flutterfire configure`, faça rebuild e '
        'publique de novo. O app abre sem push até lá.',
      );
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseCoreReady = true;
    } catch (e, st) {
      if (_isDuplicateDefaultFirebaseAppError(e)) {
        _firebaseCoreReady = true;
        debugPrint('📱 [PUSH] Firebase já inicializado (duplicate-app).');
      } else {
        _firebaseCoreReady = false;
        debugPrint(
          '📱 [PUSH] Firebase não disponível (configure Firebase / google-services): $e',
        );
        debugPrint('$st');
      }
    }
  }

  Future<void> initListenersAndLocalNotifications() async {
    // Notificações locais NÃO dependem do Firebase — usadas pra welcome,
    // foreground display de mensagens FCM e para refletir badges. Inicializa
    // sempre para o `showWelcomeNotificationIfNeeded` funcionar mesmo se
    // o Firebase ainda estiver com placeholders.
    await _ensureLocalNotificationsInitialized();

    if (!_firebaseCoreReady || _listenersAttached) {
      return;
    }
    _listenersAttached = true;

    final messaging = FirebaseMessaging.instance;

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTapPayload(message.data);
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTapPayload(initial.data);
      });
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerTokenOnBackend(token);
    });
  }

  Future<void> initFirebaseMessagingHandlers() async {
    await initListenersAndLocalNotifications();
  }

  /// Inicialização idempotente das notificações locais — pode ser chamada de
  /// vários pontos (welcome, listeners FCM, etc) sem efeito colateral.
  Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsReady) return;

    const androidInit = AndroidInitializationSettings(_smallIconResource);
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final p = response.payload;
        if (p == null || p.isEmpty) return;
        try {
          final map = jsonDecode(p) as Map<String, dynamic>;
          _handleNotificationTapPayload(
            map.map((k, v) => MapEntry(k, v?.toString() ?? '')),
          );
        } catch (_) {}
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_pushChannel);

    _localNotificationsReady = true;
  }

  Future<bool> requestUserPermission() async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        debugPrint('📱 [PUSH] Permissão de notificação negada (Android)');
        return false;
      }
    }

    // No iOS o `requestPermission` precisa do Firebase inicializado. No
    // Android a permissão de SO já foi resolvida via permission_handler
    // acima, e o requestPermission adicional só é útil quando há FCM.
    bool ok = true;
    if (_firebaseCoreReady) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!ok) {
        debugPrint(
          '📱 [PUSH] Permissão FCM não autorizada: ${settings.authorizationStatus}',
        );
      }
    }

    if (ok) {
      // Boas-vindas só uma vez por instalação — disparada após o usuário
      // aceitar notificações pra confirmar visualmente que tudo funciona.
      // Não depende do Firebase: roda local mesmo se FCM ainda não estiver
      // configurado ou o backend ainda não tiver mandado nada.
      unawaited(_showWelcomeNotificationIfNeeded());
    }

    return ok;
  }

  /// Notificação local "Bem-vindo" — disparada uma vez por instalação,
  /// imediatamente após o usuário conceder permissão. Usa o mesmo
  /// estilo (BigText + cor da marca + ícone monocromático) que as
  /// notificações reais, então serve também como preview da identidade.
  Future<void> _showWelcomeNotificationIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_welcomeShownPrefsKey) == true) {
        return;
      }

      await _ensureLocalNotificationsInitialized();
      await _showLocalNotification(
        title: 'Bem-vindo ao Intellisys',
        body:
            'Notificações ativadas. A partir de agora você recebe leads, '
            'tarefas e lembretes direto no seu celular — mesmo com o app fechado.',
      );

      await prefs.setBool(_welcomeShownPrefsKey, true);
    } catch (e) {
      debugPrint('📱 [PUSH] welcome notification: $e');
    }
  }

  /// Após login / splash com sessão válida: permissão do sistema + registo do token (FCM).
  Future<void> syncWithBackendIfAuthenticated() async {
    final hasToken = await SecureStorageService.instance.hasSavedToken();
    if (!hasToken) {
      return;
    }

    await requestUserPermission();

    if (!_firebaseCoreReady) {
      debugPrint(
        '📱 [PUSH] Firebase não inicializado (configure firebase_options / google-services). '
        'Permissão de notificações foi solicitada; push remoto ficará indisponível até configurar o Firebase.',
      );
      return;
    }

    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('📱 [PUSH] FCM getToken vazio');
      return;
    }

    debugPrint(
      '📱 [PUSH] FCM token (prefixo): ${token.length > 16 ? token.substring(0, 16) : token}…',
    );

    await _registerTokenOnBackend(token);
  }

  Future<void> unregisterFromBackendIfNeeded() async {
    final saved = await SecureStorageService.instance.getFcmTokenRegistered();
    if (saved == null || saved.isEmpty) {
      return;
    }
    try {
      await ApiService.instance.delete<void>(
        ApiConstants.notificationsMobileDevices,
        body: {'token': saved},
        retryOn401: false,
      );
    } catch (e) {
      debugPrint('📱 [PUSH] unregister API: $e');
    }
    await SecureStorageService.instance.clearFcmTokenRegistered();
  }

  Future<void> _registerTokenOnBackend(String token) async {
    final hasToken = await SecureStorageService.instance.hasSavedToken();
    if (!hasToken) {
      return;
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      final res = await ApiService.instance.post<void>(
        ApiConstants.notificationsMobileDevices,
        body: {'token': token, 'platform': platform},
      );
      if (res.success) {
        await SecureStorageService.instance.saveFcmTokenRegistered(token);
        debugPrint('📱 [PUSH] Token registrado no backend');
      } else {
        debugPrint('📱 [PUSH] Falha ao registrar token: ${res.message}');
      }
    } catch (e) {
      debugPrint('📱 [PUSH] Erro ao registrar token: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    final title = n?.title ?? message.data['title'] ?? 'Intellisys';
    final body = n?.body ??
        message.data['body'] ??
        'Abra o app para ver a notificação.';

    unawaited(NotificationController.instance.refreshUnreadCount());

    unawaited(
      _showLocalNotification(
        title: title,
        body: body,
        payload: jsonEncode(message.data),
      ),
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _pushChannel.id,
          _pushChannel.name,
          channelDescription: _pushChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIconResource,
          color: _brandRed,
          colorized: false,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'Intellisys',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // Subtítulo discreto abaixo do título — espelha o "app name" bold
          // do iOS sem precisar de Notification Service Extension.
          subtitle: 'Intellisys',
        ),
      ),
      payload: payload,
    );
  }

  void _handleNotificationTapPayload(Map<String, dynamic> data) {
    unawaited(NotificationController.instance.refreshUnreadCount());
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    final route = AppDeepLink.fromPushData(data);
    if (route != null && route.isNotEmpty) {
      nav.pushNamed(route);
      return;
    }
    nav.pushNamed(AppRoutes.notifications);
  }
}
