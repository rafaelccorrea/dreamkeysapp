import 'package:flutter/material.dart';
import '../../core/theme/theme_helpers.dart';
import '../../core/routes/app_routes.dart';
import 'app_drawer.dart';
import 'app_bottom_navigation.dart';
import '../../features/chat/widgets/chat_floating_button.dart';

/// Scaffold customizado do aplicativo com AppBar, Drawer e Bottom Navigation
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final int currentBottomNavIndex;
  final String? userName;
  final String? userEmail;
  final String? userAvatar;
  final List<Widget>? actions;
  final bool showBottomNavigation;
  final bool showDrawer;
  final PreferredSizeWidget? bottom;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.currentBottomNavIndex = 0,
    this.userName,
    this.userEmail,
    this.userAvatar,
    this.actions,
    this.showBottomNavigation = true,
    this.showDrawer = true,
    this.bottom,
  });

  /// Verifica se a rota é uma tela principal
  static bool _isMainScreen(String? routeName) {
    if (routeName == null) return false;

    return routeName == AppRoutes.home ||
        routeName == AppRoutes.properties ||
        routeName == AppRoutes.calendar ||
        routeName == AppRoutes.clients ||
        routeName == AppRoutes.profile ||
        routeName == AppRoutes.documents ||
        routeName == AppRoutes.signatures;
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    // Usar o índice baseado na rota se não foi especificado explicitamente
    final navIndex = AppBottomNavigation.getIndexForRoute(currentRoute);
    final isMainScreen = _isMainScreen(currentRoute);

    return PopScope(
      canPop: !isMainScreen, // Só permite voltar se não for tela principal
      onPopInvoked: (didPop) {
        // Se o pop não aconteceu e é uma tela principal, redireciona para o dashboard
        if (!didPop && isMainScreen) {
          // Se já estiver no home, não faz nada (mas também não permite sair)
          if (currentRoute == AppRoutes.home) {
            return;
          }
          // Redireciona para o dashboard
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.home,
            (route) => route.settings.name == AppRoutes.home,
          );
        }
      },
      child: Scaffold(
        backgroundColor: ThemeHelpers.backgroundColor(context),
        appBar: AppBar(
          title: Text(title),
          backgroundColor: ThemeHelpers.appBarBackgroundColor(context),
          foregroundColor: ThemeHelpers.textColor(context),
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: showDrawer
              ? Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          actions: actions,
          bottom: bottom,
        ),
        drawer: showDrawer
            ? AppDrawer(
                userName: userName,
                userEmail: userEmail,
                userAvatar: userAvatar,
                currentRoute: currentRoute,
              )
            : null,
        body: Stack(
          children: [
            body,
            // Botão flutuante de chat (só aparece se não estiver na tela de chat)
            if (currentRoute != AppRoutes.chat &&
                currentRoute != null &&
                !currentRoute.startsWith('/chat'))
              const ChatFloatingButton(),
          ],
        ),
        bottomNavigationBar: showBottomNavigation
            ? AppBottomNavigation(
                currentIndex: navIndex,
                onTap: (index) {
                  AppBottomNavigation.navigateToIndex(context, index);
                },
              )
            : null,
      ),
    );
  }
}
