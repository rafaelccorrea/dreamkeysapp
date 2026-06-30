import 'package:flutter/material.dart';

import '../../core/navigation/adaptive_page_route.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/theme_helpers.dart';
import '../../features/chat/widgets/chat_floating_button.dart';
import 'app_bottom_navigation.dart';
import 'app_drawer.dart';
import 'app_update_dialog.dart';
import 'minimal_body_chrome.dart';

/// Scaffold com cabeçalho minimalista no corpo (sem AppBar), drawer e bottom nav.
class AppScaffold extends StatefulWidget {
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
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  @override
  void initState() {
    super.initState();
    if (widget.showBottomNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybePromptAppUpdate(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final navIndex = AppBottomNavigation.getIndexForRoute(currentRoute);

    // Voltar NUNCA deve fechar o app a partir de uma subtela. Decidimos pelo
    // estado real da pilha:
    //  • há rota anterior (ex.: detalhe sobre a lista) → deixa o pop normal
    //    levar para a tela anterior;
    //  • é a rota raiz (a pilha foi resetada ao navegar pelo menu) → em vez de
    //    sair do app, volta para a Home. Só na própria Home o voltar é ignorado.
    final canPopRoute = Navigator.of(context).canPop();

    // Mesmo critério que [useCupertinoNativeTransitions]: iOS nativo sem web —
    // desliga o arrasto do drawer na borda para não competir com o gesto de voltar.
    final disableDrawerEdgeDrag = useCupertinoNativeTransitions;

    return PopScope(
      canPop: canPopRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentRoute == AppRoutes.home) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawerEnableOpenDragGesture:
            !(disableDrawerEdgeDrag && widget.showDrawer),
        drawer: widget.showDrawer
            ? AppDrawer(
                userName: widget.userName,
                userEmail: widget.userEmail,
                userAvatar: widget.userAvatar,
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
                  title: widget.title,
                  showDrawer: widget.showDrawer,
                  onBack: widget.showDrawer
                      ? null
                      : () => Navigator.of(context).pop(),
                  actions: widget.actions,
                ),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: widget.body),
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
        bottomNavigationBar: widget.showBottomNavigation
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
