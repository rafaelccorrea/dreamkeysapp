import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'core/constants/api_constants.dart';
import 'core/push/app_push_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/theme/app_theme.dart';
import 'core/routes/app_routes.dart';
import 'shared/services/theme_service.dart';
import 'features/notifications/controllers/notification_controller.dart';
import 'features/appointments/controllers/appointment_controller.dart';
import 'features/kanban/controllers/kanban_controller.dart';
import 'features/chat/controllers/chat_unread_controller.dart';
import 'shared/services/live_activity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiConstants.ensureInitialized();
  debugPrint('📡 [APP] API base (login/rede): ${ApiConstants.baseUrl}');

  // Inicializar dados de localização para DateFormat
  await initializeDateFormatting('pt_BR', null);

  // Inicializar serviço de tema
  await ThemeService.instance.init();

  await AppPushService.setupFirebaseBeforeRunApp();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeService.instance.addListener(_onThemeChanged);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(AppPushService.instance.initListenersAndLocalNotifications());
      unawaited(LiveActivityService.instance.bootstrap());
    });
  }

  @override
  void dispose() {
    ThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NotificationController.instance,
        ),
        ChangeNotifierProvider(create: (_) => AppointmentController.instance),
        ChangeNotifierProvider(create: (_) => KanbanController.instance),
        ChangeNotifierProvider(
          create: (_) => ChatUnreadController.instance,
        ),
      ],
      child: MaterialApp(
        title: 'Intellisys CRM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeService.instance.themeMode,
        navigatorKey: appNavigatorKey,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.generateRoute,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('pt', 'BR'),
          Locale('en', 'US'),
        ],
        locale: const Locale('pt', 'BR'),
      ),
    );
  }
}
