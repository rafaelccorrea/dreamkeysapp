import 'package:flutter/material.dart';
import '../../features/auth/login/pages/login_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_confirmation_page.dart';
import '../../features/auth/forgot_password/pages/reset_password_page.dart';
import '../../features/auth/two_factor/pages/two_factor_page.dart';
import '../../features/splash/pages/splash_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/properties/pages/properties_page.dart';
import '../../features/notifications/pages/notifications_page.dart';
import '../../features/properties/pages/property_details_page.dart';
import '../../features/properties/pages/create_property_page.dart';
import '../../features/properties/pages/property_offers_page.dart';
import '../../features/properties/pages/offer_details_page.dart';
import '../../features/appointments/pages/calendar_page.dart';
import '../../features/appointments/pages/create_appointment_page.dart';
import '../../features/appointments/pages/edit_appointment_page.dart';
import '../../features/appointments/pages/appointment_details_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/profile/pages/edit_profile_page.dart';
import '../../features/clients/pages/clients_page.dart';
import '../../features/clients/pages/client_details_page.dart';
import '../../features/clients/pages/client_form_page.dart';
import '../../features/matches/pages/matches_page.dart';
import '../../features/kanban/pages/kanban_page.dart';

/// Rotas da aplicação com transições customizadas
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String forgotPasswordConfirmation =
      '/forgot-password-confirmation';
  static const String resetPassword = '/reset-password';
  static const String twoFactor = '/two-factor';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String profileEdit = '/profile/edit';
  static const String properties = '/properties';
  static const String propertyCreate = '/properties/create';
  static const String propertyOffers = '/properties/offers';
  static const String notifications = '/notifications';
  static const String calendar = '/calendar';
  static const String calendarCreate = '/calendar/create';
  static String calendarEdit(String id) => '/calendar/edit/$id';
  static String calendarDetails(String id) => '/calendar/details/$id';

  static const String clients = '/clients';
  static const String clientCreate = '/clients/new';
  static String clientEdit(String id) => '/clients/$id/edit';
  static String clientDetails(String id) => '/clients/$id';

  // Matches
  static const String matches = '/matches';
  static String matchesByProperty(String propertyId) =>
      '/properties/$propertyId/matches';
  static String matchesByClient(String clientId) =>
      '/clients/$clientId/matches';

  // Kanban (Tarefas)
  static const String kanban = '/kanban';

  static String propertyOfferDetails(String offerId) =>
      '/properties/offers/$offerId';

  /// Gera rota de detalhes da propriedade
  static String propertyDetails(String id) => '/properties/$id';

  /// Gera rota de edição da propriedade
  static String propertyEdit(String id) => '/properties/edit/$id';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final routeName = settings.name;

    if (routeName == splash) {
      return _buildRoute(const SplashPage(), settings);
    } else if (routeName == login) {
      return _buildRoute(const LoginPage(), settings);
    } else if (routeName == forgotPassword) {
      return _buildRoute(const ForgotPasswordPage(), settings);
    } else if (routeName == forgotPasswordConfirmation) {
      final email = settings.arguments as String?;
      return _buildRoute(
        ForgotPasswordConfirmationPage(email: email),
        settings,
      );
    } else if (routeName == resetPassword) {
      final token = settings.arguments as String?;
      return _buildRoute(ResetPasswordPage(token: token), settings);
    } else if (routeName == twoFactor) {
      final args = settings.arguments as Map<String, dynamic>?;
      return _buildRoute(
        TwoFactorPage(
          email: args?['email'] ?? '',
          password: args?['password'] ?? '',
          tempToken: args?['tempToken'] ?? '',
          rememberMe: args?['rememberMe'] ?? false,
        ),
        settings,
      );
    } else if (routeName == home) {
      return _buildRoute(const DashboardPage(), settings);
    } else if (routeName == AppRoutes.settings) {
      return _buildRoute(const SettingsPage(), settings);
    } else if (routeName == AppRoutes.profile) {
      return _buildRoute(const ProfilePage(), settings);
    } else if (routeName == AppRoutes.profileEdit) {
      return _buildRoute(const EditProfilePage(), settings);
    } else if (routeName == AppRoutes.properties) {
      return _buildRoute(const PropertiesPage(), settings);
    } else if (routeName == AppRoutes.notifications) {
      return _buildRoute(const NotificationsPage(), settings);
    } else if (routeName == AppRoutes.calendar) {
      return _buildRoute(const CalendarPage(), settings);
    } else if (routeName == AppRoutes.calendarCreate) {
      return _buildRoute(const CreateAppointmentPage(), settings);
    } else if (routeName == AppRoutes.clients) {
      return _buildRoute(const ClientsPage(), settings);
    } else if (routeName == AppRoutes.clientCreate) {
      return _buildRoute(const ClientFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/calendar/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final action = segments[2];
        final id = segments.length > 3 ? segments[3] : null;

        if (action == 'edit' && id != null) {
          return _buildRoute(EditAppointmentPage(appointmentId: id), settings);
        } else if (action == 'details' && id != null) {
          return _buildRoute(
            AppointmentDetailsPage(appointmentId: id),
            settings,
          );
        }
      }
    } else if (routeName == AppRoutes.propertyCreate) {
      return _buildRoute(const CreatePropertyPage(), settings);
    } else if (routeName == AppRoutes.propertyOffers) {
      // IMPORTANTE: Esta rota deve vir ANTES da verificação genérica de /properties/
      debugPrint('🛣️ [ROUTES] Navegando para PropertyOffersPage');
      return _buildRoute(const PropertyOffersPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('/properties/offers/')) {
      // Detalhes de oferta: /properties/offers/:offerId
      final segments = routeName.split('/');
      if (segments.length == 4) {
        final offerId = segments[3];
        return _buildRoute(OfferDetailsPage(offerId: offerId), settings);
      }
    } else if (routeName != null && routeName.startsWith('/properties/')) {
      // Detalhes ou edição de propriedade (deve vir DEPOIS das rotas de ofertas)
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /properties/:id
          return _buildRoute(PropertyDetailsPage(propertyId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /properties/:id/edit
          return _buildRoute(CreatePropertyPage(propertyId: id), settings);
        }
      }
      // Se não correspondeu aos padrões acima, retornar página não encontrada
      return _buildRoute(
        const Scaffold(body: Center(child: Text('Página não encontrada'))),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/clients/')) {
      // Rotas de clientes
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /clients/:id
          return _buildRoute(ClientDetailsPage(clientId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /clients/:id/edit
          return _buildRoute(ClientFormPage(clientId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.matches) {
      return _buildRoute(const MatchesPage(), settings);
    } else if (routeName == AppRoutes.kanban) {
      return _buildRoute(const KanbanPage(), settings);
    } else if (routeName != null && routeName.startsWith('/properties/')) {
      // Matches de propriedade: /properties/:propertyId/matches
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'matches') {
        final propertyId = segments[2];
        return _buildRoute(MatchesPage(propertyId: propertyId), settings);
      }
    } else if (routeName != null && routeName.startsWith('/clients/')) {
      // Matches de cliente: /clients/:clientId/matches
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'matches') {
        final clientId = segments[2];
        return _buildRoute(MatchesPage(clientId: clientId), settings);
      }
    }

    // Rota não encontrada
    return _buildRoute(
      const Scaffold(body: Center(child: Text('Página não encontrada'))),
      settings,
    );
  }

  /// Cria uma rota com transição suave customizada
  static PageRouteBuilder<T> _buildRoute<T extends Widget>(
    Widget page,
    RouteSettings settings,
  ) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Animação de fade + slide
        const begin = Offset(0.0, 0.03);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));

        var fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: curve));

        return FadeTransition(
          opacity: animation.drive(fadeTween),
          child: SlideTransition(
            position: animation.drive(tween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}
