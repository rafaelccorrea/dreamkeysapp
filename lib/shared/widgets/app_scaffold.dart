import 'package:flutter/material.dart';
import '../../core/theme/theme_helpers.dart';
import 'app_drawer.dart';
import 'app_bottom_navigation.dart';

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

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    return Scaffold(
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
      ),
      drawer: showDrawer
          ? AppDrawer(
              userName: userName,
              userEmail: userEmail,
              userAvatar: userAvatar,
              currentRoute: currentRoute,
            )
          : null,
      body: body,
      bottomNavigationBar: showBottomNavigation && currentBottomNavIndex >= 0
          ? AppBottomNavigation(
              currentIndex: currentBottomNavIndex,
              onTap: (index) {
                AppBottomNavigation.navigateToIndex(context, index);
              },
            )
          : null,
    );
  }
}
