import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'core/constants/api_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/routes/app_routes.dart';
import 'shared/services/theme_service.dart';
import 'features/notifications/controllers/notification_controller.dart';
import 'features/appointments/controllers/appointment_controller.dart';
import 'features/kanban/controllers/kanban_controller.dart';
import 'features/chat/controllers/chat_unread_controller.dart';

// GlobalKey para o Navigator - permite navegação sem contexto
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiConstants.ensureInitialized();
  debugPrint('📡 [APP] API base (login/rede): ${ApiConstants.baseUrl}');

  // Inicializar dados de localização para DateFormat
  await initializeDateFormatting('pt_BR', null);

  // Inicializar serviço de tema
  await ThemeService.instance.init();

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
    // Escutar mudanças no tema
    ThemeService.instance.addListener(_onThemeChanged);
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
        title: 'Intellisys',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeService.instance.themeMode,
        navigatorKey: navigatorKey,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
  }
}
