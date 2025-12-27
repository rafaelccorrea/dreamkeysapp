import 'package:flutter/material.dart';
import '../../features/auth/login/pages/login_page.dart';
import '../../features/splash/pages/splash_page.dart';

/// Rotas da aplicação com transições customizadas
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _buildRoute(const SplashPage(), settings);
      case login:
        return _buildRoute(const LoginPage(), settings);
      default:
        return _buildRoute(
          const Scaffold(
            body: Center(
              child: Text('Página não encontrada'),
            ),
          ),
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

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: curve),
        );

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
