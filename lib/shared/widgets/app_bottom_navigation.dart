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
    final primaryColor = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final unselectedColor = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;
    final backgroundColor = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;

    final screenWidth = MediaQuery.of(context).size.width;
    final centerButtonWidth = 60.0;
    final centerButtonSpace =
        centerButtonWidth +
        44; // espaço para evitar que os itens colem no botão

    return Container(
      height: 70 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Barra de navegação padrão
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: SizedBox(
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Lado esquerdo: Imóveis
                  Expanded(
                    child: _buildNavItem(
                      context: context,
                      icon: currentIndex == 1
                          ? Icons.home
                          : Icons.home_outlined,
                      label: 'Imóveis',
                      isSelected: currentIndex == 1,
                      color: currentIndex == 1 ? primaryColor : unselectedColor,
                      onTap: () => onTap(1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Agenda (próximo ao centro)
                  _buildNavItem(
                    context: context,
                    icon: currentIndex == 2
                        ? Icons.calendar_today
                        : Icons.calendar_today_outlined,
                    label: 'Agenda',
                    isSelected: currentIndex == 2,
                    color: currentIndex == 2 ? primaryColor : unselectedColor,
                    onTap: () => onTap(2),
                  ),
                  // Espaço para o botão central (reduzido)
                  SizedBox(width: centerButtonSpace),
                  // Clientes (próximo ao centro)
                  _buildNavItem(
                    context: context,
                    icon: currentIndex == 3
                        ? Icons.people
                        : Icons.people_outline,
                    label: 'Clientes',
                    isSelected: currentIndex == 3,
                    color: currentIndex == 3 ? primaryColor : unselectedColor,
                    onTap: () => onTap(3),
                  ),
                  const SizedBox(width: 16),
                  // Lado direito: Perfil
                  Expanded(
                    child: _buildNavItem(
                      context: context,
                      icon: currentIndex == 4
                          ? Icons.person
                          : Icons.person_outline,
                      label: 'Perfil',
                      isSelected: currentIndex == 4,
                      color: currentIndex == 4 ? primaryColor : unselectedColor,
                      onTap: () => onTap(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Botão central elevado (Início) - apenas este tem elevação
          Positioned(
            left: screenWidth / 2 - centerButtonWidth / 2,
            top: -20,
            child: GestureDetector(
              onTap: () => onTap(0),
              child: Container(
                width: centerButtonWidth,
                height: centerButtonWidth,
                decoration: BoxDecoration(
                  color: currentIndex == 0 ? primaryColor : backgroundColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (currentIndex == 0 ? primaryColor : Colors.black)
                          .withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: currentIndex == 0
                        ? primaryColor
                        : unselectedColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  currentIndex == 0
                      ? Icons.dashboard
                      : Icons.dashboard_outlined,
                  color: currentIndex == 0 ? Colors.white : unselectedColor,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Retorna o índice da bottom navigation baseado na rota atual
  static int getIndexForRoute(String? routeName) {
    if (routeName == null) return 0;

    if (routeName == AppRoutes.home) return 0;
    if (routeName == AppRoutes.properties) return 1;
    if (routeName == AppRoutes.calendar || routeName.startsWith('/calendar'))
      return 2;
    if (routeName == AppRoutes.profile || routeName == AppRoutes.profileEdit)
      return 4;
    // Clientes ainda não implementado
    return 0;
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
        // Se já está na tela de agenda, não navega novamente
        if (currentRoute == AppRoutes.calendar) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.calendar,
          (route) => route.settings.name == AppRoutes.calendar,
        );
        break;
      case 3:
        // TODO: Navegar para clientes
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tela de Clientes em breve')));
        break;
      case 4:
        // Se já está na tela de perfil, não navega novamente
        if (currentRoute == AppRoutes.profile ||
            currentRoute == AppRoutes.profileEdit)
          return;
        Navigator.of(context).pushNamed(AppRoutes.profile);
        break;
    }
  }
}
