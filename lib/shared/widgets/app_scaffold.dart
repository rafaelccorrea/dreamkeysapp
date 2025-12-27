import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'app_bottom_navigation.dart';

/// Scaffold base do aplicativo com Drawer e Bottom Navigation
class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final bool showBottomNavigation;
  final int currentBottomNavIndex;
  final Function(int)? onBottomNavTap;
  final String? userName;
  final String? userEmail;
  final String? userAvatar;
  final bool automaticallyImplyLeading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.showBottomNavigation = true,
    this.currentBottomNavIndex = 0,
    this.onBottomNavTap,
    this.userName,
    this.userEmail,
    this.userAvatar,
    this.automaticallyImplyLeading = true,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              automaticallyImplyLeading: automaticallyImplyLeading,
              actions: actions,
            )
          : null,
      drawer: Builder(
        builder: (drawerContext) {
          final route = ModalRoute.of(drawerContext);
          final routeName = route?.settings.name;
          return AppDrawer(
            userName: userName,
            userEmail: userEmail,
            userAvatar: userAvatar,
            currentRoute: routeName,
          );
        },
      ),
      body: body,
      bottomNavigationBar: showBottomNavigation
          ? AppBottomNavigation(
              currentIndex: currentBottomNavIndex,
              onTap: onBottomNavTap ??
                  (index) {
                    AppBottomNavigation.navigateToIndex(context, index);
                  },
            )
          : null,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? FloatingActionButtonLocation.endFloat,
    );
  }
}

