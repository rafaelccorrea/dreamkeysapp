import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/constants/app_permissions.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../services/module_access_service.dart';

/// Bottom Navigation Bar — design premium 2026.
///
/// Características:
///   • Barra compacta com gradient sutil + spotlight radial deslizante que
///     segue o tab ativo (preenche o "vazio" do fundo com vida).
///   • Item ativo: squircle vibrante com gradient + ícone branco + label em
///     destaque (peso forte e cor temática).
///   • Item inativo: ícone grande sutil + label discreto.
///   • Animações coreografadas (squircle anima cor e sombra; spotlight desliza
///     com easeOutCubic; label faz tween de peso e cor).
///   • Badge de notificação refinado (gradient + halo).
///   • Suporte light/dark mode.
///   • API pública preservada (currentIndex, onTap, helpers estáticos).
class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  // ─── Tabs estáticos ─────────────────────────────────────────────────────
  static const _NavItemSpec _homeItem = _NavItemSpec(
    icon: LucideIcons.layoutDashboard,
    activeIcon: LucideIcons.layoutDashboard,
    label: 'Início',
    route: AppRoutes.home,
  );
  static const _NavItemSpec _propertiesItem = _NavItemSpec(
    icon: LucideIcons.home,
    activeIcon: LucideIcons.home,
    label: 'Imóveis',
    route: AppRoutes.properties,
  );
  static const _NavItemSpec _kanbanItem = _NavItemSpec(
    icon: LucideIcons.squareKanban,
    activeIcon: LucideIcons.squareKanban,
    label: 'CRM',
    route: AppRoutes.kanban,
  );
  static const _NavItemSpec _profileItem = _NavItemSpec(
    icon: LucideIcons.userCircle,
    activeIcon: LucideIcons.userCircle,
    label: 'Perfil',
    route: AppRoutes.profile,
  );

  // ─── Slot 3 dinâmico ────────────────────────────────────────────────────
  // Se o usuário tem permissões da fila de aprovação ⇒ "Aprovações".
  // Caso contrário ⇒ "Agenda" (calendário).
  static const _NavItemSpec _approvalsItem = _NavItemSpec(
    icon: LucideIcons.shieldCheck,
    activeIcon: LucideIcons.shieldCheck,
    label: 'Aprovações',
    route: AppRoutes.propertyApprovals,
  );
  static const _NavItemSpec _calendarItem = _NavItemSpec(
    icon: LucideIcons.calendarDays,
    activeIcon: LucideIcons.calendarDays,
    label: 'Agenda',
    route: AppRoutes.calendar,
  );

  /// Resolve o item que ocupa o slot 3 com base nas permissões atuais.
  static _NavItemSpec _resolveSlot3() {
    final canSeeApprovals = ModuleAccessService.instance
        .hasAnyPermission(AppPermissions.approvalQueueMenu);
    return canSeeApprovals ? _approvalsItem : _calendarItem;
  }

  static List<_NavItemSpec> _resolveItems() => [
        _homeItem,
        _propertiesItem,
        _kanbanItem,
        _resolveSlot3(),
        _profileItem,
      ];

  @override
  Widget build(BuildContext context) {
    // Reage a login/logout/troca de empresa que alteram permissões.
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
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
    final items = _resolveItems();
    final itemCount = items.length;

    // Quando o índice é inválido (rota fora do nav), não anima nem destaca.
    final bool hasActiveTab = currentIndex >= 0 && currentIndex < itemCount;
    final double indicatorAlignment = !hasActiveTab
        ? -2.0
        : (itemCount <= 1 ? 0 : (currentIndex / (itemCount - 1)) * 2 - 1);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF1B2030),
                  const Color(0xFF11151E),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF7F8FB),
                ],
        ),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE4E7EC),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, -10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 6, bottomInset > 0 ? 4 : 8),
          child: SizedBox(
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1) Spotlight radial que segue o tab ativo (preenche o fundo).
                if (hasActiveTab)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedAlign(
                        alignment: Alignment(indicatorAlignment, 0),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        child: FractionallySizedBox(
                          widthFactor: 1 / itemCount * 1.6,
                          heightFactor: 1.4,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.center,
                                radius: 0.7,
                                colors: [
                                  primaryColor.withValues(
                                    alpha: isDark ? 0.16 : 0.10,
                                  ),
                                  primaryColor.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // 2) Hairline horizontal no topo, sutil acento da marca.
                if (hasActiveTab)
                  Positioned(
                    top: -4,
                    left: 0,
                    right: 0,
                    child: AnimatedAlign(
                      alignment: Alignment(indicatorAlignment, 0),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      child: FractionallySizedBox(
                        widthFactor: 1 / itemCount,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  primaryColor.withValues(alpha: 0.0),
                                  primaryColor,
                                  primaryDeep,
                                  primaryColor.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.3, 0.7, 1.0],
                              ),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withValues(alpha: 0.55),
                                  blurRadius: 8,
                                  spreadRadius: 0.2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // 3) Tabs.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(itemCount, (i) {
                    final spec = items[i];
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int getIndexForRoute(String? routeName) {
    if (routeName == null) return 0;

    if (routeName == AppRoutes.home) return 0;

    // IMPORTANTE: Aprovações precisa ser detectada ANTES de /properties porque
    // a rota é '/properties/pending-approvals'.
    if (routeName == AppRoutes.propertyApprovals) return 3;

    if (routeName == AppRoutes.properties ||
        routeName.startsWith('/properties')) {
      return 1;
    }
    if (routeName == AppRoutes.kanban || routeName.startsWith('/kanban')) {
      return 2;
    }
    if (routeName == AppRoutes.calendar ||
        routeName.startsWith('/calendar')) {
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
      return 4;
    }
    // Rotas que não estão na bottom nav (ex.: /clients) → nenhum tab ativo.
    return -1;
  }

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
        final slot3Route = _resolveSlot3().route;
        if (currentRoute == slot3Route) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          slot3Route,
          (route) => route.settings.name == slot3Route,
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

    const Color activeIconColor = Colors.white;
    final Color activeLabelColor = isDark ? Colors.white : primaryDeep;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: primaryColor.withValues(alpha: 0.14),
        highlightColor: primaryColor.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Squircle do ícone — vibrante quando ativo.
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 34,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primaryColor,
                            primaryDeep,
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? primaryDeep.withValues(alpha: 0.35)
                        : Colors.transparent,
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: primaryColor.withValues(
                              alpha: isDark ? 0.55 : 0.40,
                            ),
                            blurRadius: 14,
                            spreadRadius: 0.3,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: primaryDeep.withValues(alpha: 0.25),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween<double>(begin: 0.80, end: 1.0)
                              .animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          isSelected ? spec.activeIcon : spec.icon,
                          key: ValueKey<bool>(isSelected),
                          size: 23,
                          color:
                              isSelected ? activeIconColor : inactiveColor,
                        ),
                      ),
                      if (notificationCount > 0)
                        Positioned(
                          right: -10,
                          top: -8,
                          child: _NotificationBadge(
                            count: notificationCount,
                            backgroundColor: backgroundColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // Label sempre visível, com hierarquia clara.
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: isSelected ? activeLabelColor : inactiveColor,
                  fontSize: isSelected ? 11.5 : 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: 0.15,
                  height: 1.05,
                ),
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({
    required this.count,
    required this.backgroundColor,
  });

  final int count;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    const Color badgeColor = Color(0xFFEF4444);
    const Color badgeDeep = Color(0xFFB91C1C);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [badgeColor, badgeDeep],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: backgroundColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.55),
            blurRadius: 8,
            spreadRadius: 0.5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0.2,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
