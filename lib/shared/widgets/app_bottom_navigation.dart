import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../features/notifications/controllers/notification_controller.dart';

/// Bottom Navigation Bar do aplicativo.
///
/// Redesign 2026:
///   • Sem botão central elevado (que atrapalhava a usabilidade).
///   • Todos os tabs no mesmo nível, espaçados igualmente.
///   • Indicador "pill" animado atrás do item ativo.
///   • Item ativo: pill com gradient suave + ícone + label.
///   • Itens inativos: apenas ícone (label aparece com leve fade).
///   • Suporte ao tema (light/dark) preservado.
///   • Badges de notificação preservados.
///
/// A API pública (currentIndex, onTap, helpers estáticos) é a mesma da
/// versão anterior — para não exigir alteração nas telas que já usam.
class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavItemSpec> _items = [
    _NavItemSpec(
      icon: LucideIcons.layoutDashboard,
      activeIcon: LucideIcons.layoutDashboard,
      label: 'Início',
      route: AppRoutes.home,
    ),
    _NavItemSpec(
      icon: LucideIcons.home,
      activeIcon: LucideIcons.home,
      label: 'Imóveis',
      route: AppRoutes.properties,
    ),
    _NavItemSpec(
      icon: LucideIcons.squareKanban,
      activeIcon: LucideIcons.squareKanban,
      label: 'Funís',
      route: AppRoutes.kanban,
    ),
    _NavItemSpec(
      icon: LucideIcons.users,
      activeIcon: LucideIcons.users,
      label: 'Clientes',
      route: AppRoutes.clients,
    ),
    _NavItemSpec(
      icon: LucideIcons.userCircle,
      activeIcon: LucideIcons.userCircle,
      label: 'Perfil',
      route: AppRoutes.profile,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final primaryDeep = isDark
        ? AppColors.primary.primaryDark
        : AppColors.primary.primaryDarker;
    final unselectedColor = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;
    final backgroundColor = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, bottomInset > 0 ? 4 : 8),
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_items.length, (i) {
                final spec = _items[i];
                final isSelected = currentIndex == i;
                return Expanded(
                  child: _NavTab(
                    spec: spec,
                    isSelected: isSelected,
                    primaryColor: primaryColor,
                    primaryDeep: primaryDeep,
                    inactiveColor: unselectedColor,
                    backgroundColor: backgroundColor,
                    isDark: isDark,
                    onTap: () => onTap(i),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  /// Retorna o índice da bottom navigation baseado na rota atual.
  static int getIndexForRoute(String? routeName) {
    if (routeName == null) return 0;

    if (routeName == AppRoutes.home) return 0;
    if (routeName == AppRoutes.properties ||
        routeName.startsWith('/properties')) {
      return 1;
    }
    if (routeName == AppRoutes.kanban || routeName.startsWith('/kanban')) {
      return 2;
    }
    if (routeName == AppRoutes.clients || routeName.startsWith('/clients')) {
      return 3;
    }
    if (routeName == AppRoutes.profile ||
        routeName == AppRoutes.profileEdit ||
        routeName == AppRoutes.documents ||
        routeName == AppRoutes.signatures ||
        routeName == AppRoutes.chat ||
        routeName.startsWith('/documents') ||
        routeName.startsWith('/signatures') ||
        routeName.startsWith('/chat')) {
      // Documentos, assinaturas e chat ficam no mesmo grupo do perfil
      return 4;
    }
    return 0;
  }

  /// Navega para a tela correspondente ao índice.
  static void navigateToIndex(BuildContext context, int index) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    switch (index) {
      case 0:
        if (currentRoute == AppRoutes.home) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => route.settings.name == AppRoutes.home,
        );
        break;
      case 1:
        if (currentRoute == AppRoutes.properties) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.properties,
          (route) => route.settings.name == AppRoutes.properties,
        );
        break;
      case 2:
        if (currentRoute == AppRoutes.kanban) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.kanban,
          (route) => route.settings.name == AppRoutes.kanban,
        );
        break;
      case 3:
        if (currentRoute == AppRoutes.clients) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.clients,
          (route) => route.settings.name == AppRoutes.clients,
        );
        break;
      case 4:
        if (currentRoute == AppRoutes.profile ||
            currentRoute == AppRoutes.profileEdit) {
          return;
        }
        Navigator.of(context).pushNamed(AppRoutes.profile);
        break;
    }
  }
}

class _NavItemSpec {
  const _NavItemSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.spec,
    required this.isSelected,
    required this.primaryColor,
    required this.primaryDeep,
    required this.inactiveColor,
    required this.backgroundColor,
    required this.isDark,
    required this.onTap,
  });

  final _NavItemSpec spec;
  final bool isSelected;
  final Color primaryColor;
  final Color primaryDeep;
  final Color inactiveColor;
  final Color backgroundColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    int notificationCount = 0;
    if (spec.route.isNotEmpty) {
      try {
        final notificationController = context.watch<NotificationController>();
        notificationCount = notificationController.getCountForRoute(spec.route);
      } catch (_) {
        // Sem controller disponível: ignora silenciosamente.
      }
    }

    final Color activeFg = isDark ? Colors.white : primaryDeep;

    final Decoration activeDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                primaryColor.withValues(alpha: 0.30),
                primaryDeep.withValues(alpha: 0.18),
              ]
            : [
                primaryColor.withValues(alpha: 0.14),
                primaryColor.withValues(alpha: 0.06),
              ],
      ),
      border: Border.all(
        color: isDark
            ? primaryColor.withValues(alpha: 0.35)
            : primaryColor.withValues(alpha: 0.25),
        width: 1,
      ),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: primaryColor.withValues(alpha: isDark ? 0.30 : 0.20),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    final Decoration inactiveDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      border: Border.all(color: Colors.transparent, width: 1),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: primaryColor.withValues(alpha: 0.12),
        highlightColor: primaryColor.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 10 : 8,
            vertical: 8,
          ),
          decoration: isSelected ? activeDecoration : inactiveDecoration,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected ? spec.activeIcon : spec.icon,
                      key: ValueKey<bool>(isSelected),
                      size: isSelected ? 22 : 22,
                      color: isSelected ? activeFg : inactiveColor,
                    ),
                  ),
                  if (notificationCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: backgroundColor,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notificationCount > 99 ? '99+' : '$notificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              // Label aparece somente no item selecionado (transição suave).
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axis: Axis.horizontal,
                      child: child,
                    ),
                  ),
                  child: isSelected
                      ? Padding(
                          key: const ValueKey('label-on'),
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            spec.label,
                            style: TextStyle(
                              color: activeFg,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('label-off')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
