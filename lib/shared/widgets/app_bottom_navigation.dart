import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';

/// Bottom Navigation Bar do aplicativo
class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: isDark 
          ? AppColors.primary.primaryDarkMode 
          : AppColors.primary.primary,
      unselectedItemColor: isDark
          ? AppColors.text.textSecondaryDarkMode
          : AppColors.text.textSecondary,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      backgroundColor: isDark
          ? AppColors.background.cardBackgroundDarkMode
          : AppColors.background.cardBackground,
      elevation: 8,
      items: [
        BottomNavigationBarItem(
          icon: Icon(
            currentIndex == 0 ? Icons.dashboard : Icons.dashboard_outlined,
          ),
          label: 'Início',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            currentIndex == 1 ? Icons.home : Icons.home_outlined,
          ),
          label: 'Imóveis',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            currentIndex == 2 ? Icons.calendar_today : Icons.calendar_today_outlined,
          ),
          label: 'Agenda',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            currentIndex == 3 ? Icons.chat_bubble : Icons.chat_bubble_outline,
          ),
          label: 'Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            currentIndex == 4 ? Icons.person : Icons.person_outline,
          ),
          label: 'Perfil',
        ),
      ],
    );
  }

  /// Navega para a tela correspondente ao índice
  static void navigateToIndex(BuildContext context, int index) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    switch (index) {
      case 0:
        // Se já está na tela home, não navega novamente
        if (currentRoute == AppRoutes.home) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => route.settings.name == AppRoutes.home,
        );
        break;
      case 1:
        // Se já está na tela de propriedades, não navega novamente
        if (currentRoute == AppRoutes.properties) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.properties,
          (route) => route.settings.name == AppRoutes.properties,
        );
        break;
      case 2:
        // TODO: Navegar para agenda
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tela de Agenda em breve')),
        );
        break;
      case 3:
        // TODO: Navegar para chat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tela de Chat em breve')),
        );
        break;
      case 4:
        // Se já está na tela de configurações, não navega novamente
        if (currentRoute == AppRoutes.settings) return;
        // Navegar para configurações (temporariamente, depois criar tela de perfil)
        Navigator.of(context).pushNamed(AppRoutes.settings);
        break;
    }
  }
}

