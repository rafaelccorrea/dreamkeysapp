import 'package:flutter/material.dart';
import '../../features/auth/login/pages/login_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_confirmation_page.dart';
import '../../features/auth/forgot_password/pages/reset_password_page.dart';
import '../../features/auth/two_factor/pages/two_factor_page.dart';
import '../../features/splash/pages/splash_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/settings/pages/settings_page.dart';

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
    } else {
      return _buildRoute(
        const Scaffold(body: Center(child: Text('Página não encontrada'))),
        settings,
      );
    }
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
