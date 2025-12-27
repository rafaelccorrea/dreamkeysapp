import 'package:flutter/material.dart';
import '../../../main.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/token_refresh_service.dart';
import '../services/company_service.dart';
import 'package:dreamkeys_corretor_app/shared/widgets/permission_wrapper.dart';

/// Drawer (menu lateral) do aplicativo
class AppDrawer extends StatefulWidget {
  final String? userName;
  final String? userEmail;
  final String? userAvatar;
  final String? currentRoute;

  const AppDrawer({
    super.key,
    this.userName,
    this.userEmail,
    this.userAvatar,
    this.currentRoute,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String? _companyName;
  bool _isLoadingCompany = true;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    try {
      final companyService = CompanyService.instance;
      final response = await companyService.getSelectedCompany();

      if (mounted) {
        setState(() {
          _companyName = response.data?.name;
          _isLoadingCompany = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [APP_DRAWER] Erro ao carregar empresa: $e');
      if (mounted) {
        setState(() {
          _isLoadingCompany = false;
        });
      }
    }
  }

  String _getCurrentRoute(BuildContext context) {
    if (widget.currentRoute != null && widget.currentRoute!.isNotEmpty) {
      return widget.currentRoute!;
    }
    // Tentar pegar do ModalRoute
    final route = ModalRoute.of(context);
    return route?.settings.name ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = _getCurrentRoute(context);

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Header do Drawer - adapta cor primária ao tema
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? AppColors.primary.primaryDarkMode
                  : AppColors.primary.primary,
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    backgroundImage: widget.userAvatar != null
                        ? NetworkImage(widget.userAvatar!)
                        : null,
                    child: widget.userAvatar == null
                        ? Text(
                            (widget.userName ?? 'U')[0].toUpperCase(),
                            style: TextStyle(
                              color: theme.brightness == Brightness.dark
                                  ? AppColors.primary.primaryDarkMode
                                  : AppColors.primary.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.userName ?? 'Usuário',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.userEmail ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                  if (_companyName != null && _companyName!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.business,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _companyName!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isLoadingCompany) ...[
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: AppRoutes.home,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  title: 'Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    // Se já está na tela home, não navega novamente
                    if (activeRoute == AppRoutes.home) return;
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
                  },
                ),
                PermissionWrapper(
                  moduleId: 'property_management',
                  permission: 'property:view',
                  child: _buildDrawerItem(
                    context: context,
                    currentRoute: activeRoute,
                    route: AppRoutes.properties,
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    title: 'Imóveis',
                    onTap: () {
                      Navigator.pop(context);
                      // Se já está na tela de propriedades, não navega novamente
                      if (activeRoute == AppRoutes.properties) return;
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.properties,
                        (route) => false,
                      );
                    },
                  ),
                ),
                PermissionWrapper(
                  moduleId: 'client_management',
                  permission: 'client:view',
                  child: _buildDrawerItem(
                    context: context,
                    currentRoute: activeRoute,
                    route: '/clients',
                    icon: Icons.people_outlined,
                    activeIcon: Icons.people,
                    title: 'Clientes',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: Navegar para tela de clientes
                      _showComingSoon(context);
                    },
                  ),
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/appointments',
                  icon: Icons.calendar_today_outlined,
                  activeIcon: Icons.calendar_today,
                  title: 'Agenda',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de agenda
                    _showComingSoon(context);
                  },
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/matches',
                  icon: Icons.favorite_outline,
                  activeIcon: Icons.favorite,
                  title: 'Matches',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de matches
                    _showComingSoon(context);
                  },
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/commissions',
                  icon: Icons.attach_money_outlined,
                  activeIcon: Icons.attach_money,
                  title: 'Comissões',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de comissões
                    _showComingSoon(context);
                  },
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/chat',
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  title: 'Mensagens',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de chat
                    _showComingSoon(context);
                  },
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/tasks',
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment,
                  title: 'Tarefas',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de tarefas
                    _showComingSoon(context);
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '/profile',
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  title: 'Perfil',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navegar para tela de perfil
                    _showComingSoon(context);
                  },
                ),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: AppRoutes.settings,
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  title: 'Configurações',
                  onTap: () {
                    Navigator.pop(context);
                    // Se já está na tela de configurações, não navega novamente
                    if (activeRoute == AppRoutes.settings) return;
                    Navigator.of(context).pushNamed(AppRoutes.settings);
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '',
                  icon: Icons.logout,
                  activeIcon: Icons.logout,
                  title: 'Sair',
                  onTap: () {
                    _handleLogout(context);
                  },
                  isDestructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required String currentRoute,
    required String route,
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    final active = isActive || (currentRoute == route && route.isNotEmpty);

    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark 
        ? AppColors.primary.primaryDarkMode 
        : AppColors.primary.primary;
    
    final color = isDestructive
        ? theme.colorScheme.error
        : active
        ? primaryColor
        : theme.colorScheme.onSurface;

    final iconToShow = active ? activeIcon : icon;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(iconToShow, color: color),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidade em breve'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    // Fechar o drawer primeiro
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // Aguardar um pouco para garantir que o drawer foi fechado
    await Future.delayed(const Duration(milliseconds: 200));

    // Verificar se o contexto ainda está válido para mostrar o diálogo
    if (!context.mounted) {
      debugPrint('⚠️ [LOGOUT] Contexto não está mais montado');
      return;
    }

    // Mostrar diálogo de confirmação
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Tem certeza que deseja sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        debugPrint('🚪 [LOGOUT] Usuário confirmou logout');

        // Parar serviço de refresh periódico
        TokenRefreshService.instance.stopPeriodicRefresh();
        debugPrint('🛑 [LOGOUT] Serviço de refresh parado');

        // Fazer logout (aguardar conclusão)
        debugPrint('🚪 [LOGOUT] Iniciando processo de logout...');
        await AuthService.instance.logout();
        debugPrint('✅ [LOGOUT] Logout concluído');

        // Navegar para login usando o navigatorKey global
        // Isso funciona mesmo se o contexto foi perdido
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushNamedAndRemoveUntil(
            AppRoutes.login,
            (route) => false,
          );
          debugPrint('🔄 [LOGOUT] Redirecionado para tela de login');
        } else {
          debugPrint('❌ [LOGOUT] NavigatorKey não está disponível');
          // Fallback: tentar usar o contexto se ainda estiver montado
          if (context.mounted) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
            debugPrint('🔄 [LOGOUT] Redirecionado usando contexto');
          }
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [LOGOUT] Erro durante logout: $e');
        debugPrint('📚 [LOGOUT] StackTrace: $stackTrace');

        // Mesmo com erro, tentar navegar para login usando navigatorKey
        try {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.pushNamedAndRemoveUntil(
              AppRoutes.login,
              (route) => false,
            );
            debugPrint('🔄 [LOGOUT] Redirecionado para login após erro');
          } else if (context.mounted) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
            debugPrint('🔄 [LOGOUT] Redirecionado usando contexto após erro');
          }
        } catch (navError) {
          debugPrint('❌ [LOGOUT] Erro ao navegar: $navError');
        }
      }
    } else {
      debugPrint('ℹ️ [LOGOUT] Logout cancelado pelo usuário');
    }
  }
}
