import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/api_constants.dart';
import '../navigation/app_navigator.dart';
import '../routes/app_routes.dart';
import '../../firebase_options.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/secure_storage_service.dart';

const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  'imobx_alerts',
  'Alertas do sistema',
  description: 'Notificações do Intellisys (leads, tarefas, agenda…)',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _firebaseCoreReady = false;
bool _listenersAttached = false;

bool _firebaseOptionsLookLikePlaceholder() {
  const k = 'REPLACE_WITH';
  return DefaultFirebaseOptions.android.apiKey.contains(k) ||
      DefaultFirebaseOptions.android.appId.contains(k) ||
      DefaultFirebaseOptions.android.projectId.contains(k);
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
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('📱 [PUSH] Background Firebase init: $e');
    return;
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
    await _localNotifications.show(
      id: message.messageId?.hashCode.abs() ??
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title.isEmpty ? 'Intellisys' : title,
      body: body.isEmpty ? 'Abra o app para ver a notificação.' : body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _pushChannel.id,
          _pushChannel.name,
          channelDescription: _pushChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
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

    if (_firebaseOptionsLookLikePlaceholder()) {
      debugPrint(
        '📱 [PUSH] firebase_options.dart ainda tem placeholders — '
        'execute `flutterfire configure` e substitua google-services.json.',
      );
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseCoreReady = true;
    } catch (e, st) {
      _firebaseCoreReady = false;
      debugPrint(
        '📱 [PUSH] Firebase não disponível (configure Firebase / google-services): $e',
      );
      debugPrint('$st');
    }
  }

  Future<void> initListenersAndLocalNotifications() async {
    if (!_firebaseCoreReady || _listenersAttached) {
      return;
    }
    _listenersAttached = true;

    await _setupLocalNotifications();

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

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!ok) {
      debugPrint(
        '📱 [PUSH] Permissão FCM não autorizada: ${settings.authorizationStatus}',
      );
    }
    return ok;
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
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _handleNotificationTapPayload(Map<String, dynamic> data) {
    unawaited(NotificationController.instance.refreshUnreadCount());
    if (appNavigatorKey.currentState != null) {
      appNavigatorKey.currentState!.pushNamed(AppRoutes.notifications);
    }
  }
}
