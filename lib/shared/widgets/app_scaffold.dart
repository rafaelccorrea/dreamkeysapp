import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import '../../core/routes/app_routes.dart';
import '../../core/theme/theme_helpers.dart';
import '../../features/chat/widgets/chat_floating_button.dart';
import 'app_bottom_navigation.dart';
import 'app_drawer.dart';
import 'minimal_body_chrome.dart';

/// Scaffold com cabeçalho minimalista no corpo (sem AppBar), drawer e bottom nav.
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
  });

  static bool _isMainScreen(String? routeName) {
    if (routeName == null) return false;

    return routeName == AppRoutes.home ||
        routeName == AppRoutes.properties ||
        routeName == AppRoutes.kanban ||
        routeName == AppRoutes.clients ||
        routeName == AppRoutes.profile ||
        routeName == AppRoutes.documents ||
        routeName == AppRoutes.signatures;
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final navIndex = AppBottomNavigation.getIndexForRoute(currentRoute);
    final isMainScreen = _isMainScreen(currentRoute);

    final isIosPhone =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return PopScope(
      canPop: !isMainScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isMainScreen) {
          if (currentRoute == AppRoutes.home) {
            return;
          }
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.home,
            (route) => route.settings.name == AppRoutes.home,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawerEnableOpenDragGesture: !(isIosPhone && showDrawer),
        drawer: showDrawer
            ? AppDrawer(
                userName: userName,
                userEmail: userEmail,
                userAvatar: userAvatar,
                currentRoute: currentRoute,
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: ThemeHelpers.shellBackgroundDecoration(context),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MinimalBodyChrome(
                  title: title,
                  showDrawer: showDrawer,
                  onBack: showDrawer ? null : () => Navigator.of(context).pop(),
                  actions: actions,
                ),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: body),
                      if (currentRoute != AppRoutes.chat &&
                          currentRoute != null &&
                          !currentRoute.startsWith('/chat'))
                        const ChatFloatingButton(),
                    ],
                  ),
                ),
              ],
            ),
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
