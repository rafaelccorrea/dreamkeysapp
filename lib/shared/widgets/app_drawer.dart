import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../main.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/token_refresh_service.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/dashboard_service.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/chat/controllers/chat_unread_controller.dart';

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

  // Dados do usuário carregados do serviço
  String? _loadedUserName;
  String? _loadedUserEmail;
  String? _loadedUserAvatar;
  bool _isLoadingProfile = false;

  // Estado dos expansion tiles
  bool _gestaoExpanded = false;
  bool _documentosExpanded = false;
  bool _gestaoInternaExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadCompany();
    // Sempre tentar carregar perfil, mas priorizar dados fornecidos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
      _checkActiveRoutes();
    });
  }

  void _checkActiveRoutes() {
    if (!mounted) return;
    final activeRoute = _getCurrentRoute();

    // Verificar se algum item de Gestão de Negócios está ativo
    if (activeRoute == AppRoutes.properties ||
        activeRoute == AppRoutes.clients ||
        activeRoute == AppRoutes.matches ||
        activeRoute == AppRoutes.calendar ||
        activeRoute.startsWith('/clients')) {
      setState(() {
        _gestaoExpanded = true;
      });
    }

    // Verificar se algum item de Documentos está ativo
    if (activeRoute == AppRoutes.documents ||
        activeRoute == AppRoutes.signatures ||
        activeRoute.startsWith('/documents')) {
      setState(() {
        _documentosExpanded = true;
      });
    }

    // Verificar se algum item de Gestão Interna está ativo
    if (activeRoute == AppRoutes.kanban ||
        activeRoute == AppRoutes.inspections ||
        activeRoute == AppRoutes.keys ||
        activeRoute.startsWith('/inspections') ||
        activeRoute.startsWith('/keys')) {
      setState(() {
        _gestaoInternaExpanded = true;
      });
    }
  }

  @override
  void didUpdateWidget(AppDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se os parâmetros mudaram e agora temos dados, não precisa recarregar
    // Se os parâmetros foram removidos, recarregar
    if ((oldWidget.userName != null || oldWidget.userEmail != null) &&
        (widget.userName == null || widget.userEmail == null)) {
      // Dados foram removidos, recarregar
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    // Se já temos os dados completos via parâmetros, não precisa carregar
    if (widget.userName != null &&
        widget.userName!.isNotEmpty &&
        widget.userEmail != null &&
        widget.userEmail!.isNotEmpty) {
      debugPrint(
        '✅ [APP_DRAWER] Dados do usuário já fornecidos via parâmetros',
      );
      // Limpar dados carregados anteriormente se agora temos via parâmetros
      if (_loadedUserName != null || _loadedUserEmail != null) {
        setState(() {
          _loadedUserName = null;
          _loadedUserEmail = null;
          _loadedUserAvatar = null;
        });
      }
      return;
    }

    // Se já temos dados carregados, não precisa recarregar
    if (_loadedUserName != null &&
        _loadedUserEmail != null &&
        !_isLoadingProfile) {
      debugPrint('✅ [APP_DRAWER] Dados do usuário já carregados anteriormente');
      return;
    }

    debugPrint('📡 [APP_DRAWER] Carregando perfil do usuário...');

    setState(() {
      _isLoadingProfile = true;
    });

    try {
      // Tentar primeiro o ProfileService
      final profileService = ProfileService.instance;
      final profileResponse = await profileService.getProfile();

      debugPrint(
        '📡 [APP_DRAWER] Resposta do perfil: success=${profileResponse.success}',
      );

      if (profileResponse.success && profileResponse.data != null) {
        if (mounted) {
          setState(() {
            _loadedUserName = profileResponse.data!.name;
            _loadedUserEmail = profileResponse.data!.email;
            _loadedUserAvatar = profileResponse.data!.avatar;
            debugPrint(
              '✅ [APP_DRAWER] Perfil carregado via ProfileService: ${profileResponse.data!.name} (${profileResponse.data!.email})',
            );
            _isLoadingProfile = false;
          });
        }
        return;
      }

      // Se ProfileService falhou, tentar DashboardService como fallback
      debugPrint(
        '⚠️ [APP_DRAWER] ProfileService falhou, tentando DashboardService como fallback...',
      );
      final dashboardService = DashboardService.instance;
      final dashboardResponse = await dashboardService.getUserDashboard();

      if (mounted) {
        setState(() {
          if (dashboardResponse.success && dashboardResponse.data != null) {
            _loadedUserName = dashboardResponse.data!.user.name;
            _loadedUserEmail = dashboardResponse.data!.user.email;
            _loadedUserAvatar = dashboardResponse.data!.user.avatar;
            debugPrint(
              '✅ [APP_DRAWER] Perfil carregado via DashboardService: ${dashboardResponse.data!.user.name} (${dashboardResponse.data!.user.email})',
            );
          } else {
            debugPrint(
              '❌ [APP_DRAWER] Erro ao carregar perfil (ambos os serviços falharam): ${dashboardResponse.message}',
            );
          }
          _isLoadingProfile = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APP_DRAWER] Erro ao carregar perfil: $e');
      debugPrint('📚 [APP_DRAWER] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
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

  // Métodos para obter os dados do usuário (prioriza parâmetros, depois dados carregados)
  String? get _userName => widget.userName ?? _loadedUserName;
  String? get _userEmail => widget.userEmail ?? _loadedUserEmail;
  String? get _userAvatar => widget.userAvatar ?? _loadedUserAvatar;

  String _getCurrentRoute() {
    if (widget.currentRoute != null && widget.currentRoute!.isNotEmpty) {
      return widget.currentRoute!;
    }
    final route = ModalRoute.of(context);
    return route?.settings.name ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = _getCurrentRoute();

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
                  if (_isLoadingProfile)
                    const SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).pushNamed(AppRoutes.profile);
                      },
                      borderRadius: BorderRadius.circular(32),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white,
                        backgroundImage: _userAvatar != null
                            ? NetworkImage(_userAvatar!)
                            : null,
                        child: _userAvatar == null
                            ? Text(
                                (_userName ?? 'U')[0].toUpperCase(),
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
                    ),
                  const SizedBox(height: 16),
                  if (_isLoadingProfile)
                    const SizedBox(
                      width: 120,
                      height: 20,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Text(
                      _userName ?? 'Usuário',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (_isLoadingProfile)
                    const SizedBox(
                      width: 100,
                      height: 16,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Text(
                      _userEmail ?? '',
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
                            LucideIcons.building2,
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
                // Dashboard (item principal, sem grupo)
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: AppRoutes.home,
                  icon: LucideIcons.layoutDashboard,
                  activeIcon: LucideIcons.layoutDashboard,
                  title: 'Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    if (activeRoute == AppRoutes.home) return;
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
                  },
                ),
                const Divider(),

                // Gestão de Negócios (ExpansionTile)
                _buildExpansionTile(
                  context: context,
                  currentRoute: activeRoute,
                  title: 'Gestão de Negócios',
                  icon: LucideIcons.building2,
                  activeIcon: LucideIcons.building2,
                  isExpanded: _gestaoExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _gestaoExpanded = expanded;
                    });
                  },
                  children: [
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.properties,
                      icon: LucideIcons.home,
                      activeIcon: LucideIcons.home,
                      title: 'Imóveis',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.properties) return;
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.properties,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.clients,
                      icon: LucideIcons.users,
                      activeIcon: LucideIcons.users,
                      title: 'Clientes',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.clients ||
                            activeRoute.startsWith('/clients')) {
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.clients,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.matches,
                      icon: LucideIcons.heart,
                      activeIcon: LucideIcons.heart,
                      title: 'Matches',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.matches) return;
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.matches,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.calendar,
                      icon: LucideIcons.calendar,
                      activeIcon: LucideIcons.calendar,
                      title: 'Agenda',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.calendar) return;
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.calendar,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                  ],
                ),

                // Documentos e Contratos (ExpansionTile)
                _buildExpansionTile(
                  context: context,
                  currentRoute: activeRoute,
                  title: 'Documentos e Contratos',
                  icon: LucideIcons.folder,
                  activeIcon: LucideIcons.folder,
                  isExpanded: _documentosExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _documentosExpanded = expanded;
                    });
                  },
                  children: [
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.documents,
                      icon: LucideIcons.fileText,
                      activeIcon: LucideIcons.fileText,
                      title: 'Documentos',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.documents ||
                            activeRoute.startsWith('/documents')) {
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.documents,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.signatures,
                      icon: LucideIcons.penTool,
                      activeIcon: LucideIcons.penTool,
                      title: 'Assinaturas',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.signatures) {
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.signatures,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                  ],
                ),

                // Mensagens (item único, sem grupo)
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: AppRoutes.chat,
                  icon: LucideIcons.messageCircle,
                  activeIcon: LucideIcons.messageCircle,
                  title: 'Mensagens',
                  onTap: () {
                    Navigator.pop(context);
                    if (activeRoute == AppRoutes.chat ||
                        activeRoute.startsWith('/chat')) {
                      return;
                    }
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.chat, (route) => false);
                  },
                ),

                // Gestão Interna (ExpansionTile)
                _buildExpansionTile(
                  context: context,
                  currentRoute: activeRoute,
                  title: 'Gestão Interna',
                  icon: LucideIcons.briefcase,
                  activeIcon: LucideIcons.briefcase,
                  isExpanded: _gestaoInternaExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _gestaoInternaExpanded = expanded;
                    });
                  },
                  children: [
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.kanban,
                      icon: LucideIcons.clipboardList,
                      activeIcon: LucideIcons.clipboardList,
                      title: 'Tarefas',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.kanban) return;
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.kanban,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.inspections,
                      icon: LucideIcons.clipboardCheck,
                      activeIcon: LucideIcons.clipboardCheck,
                      title: 'Vistorias',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.inspections ||
                            activeRoute.startsWith('/inspections')) {
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.inspections,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: AppRoutes.keys,
                      icon: LucideIcons.key,
                      activeIcon: LucideIcons.key,
                      title: 'Chaves',
                      onTap: () {
                        Navigator.pop(context);
                        if (activeRoute == AppRoutes.keys ||
                            activeRoute.startsWith('/keys')) {
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.keys,
                          (route) => false,
                        );
                      },
                      isSubItem: true,
                    ),
                    _buildDrawerItem(
                      context: context,
                      currentRoute: activeRoute,
                      route: '/commissions',
                      icon: LucideIcons.dollarSign,
                      activeIcon: LucideIcons.dollarSign,
                      title: 'Comissões',
                      onTap: () {
                        Navigator.pop(context);
                        _showComingSoon(context);
                      },
                      isSubItem: true,
                    ),
                  ],
                ),

                const Divider(),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: AppRoutes.settings,
                  icon: LucideIcons.settings,
                  activeIcon: LucideIcons.settings,
                  title: 'Configurações',
                  onTap: () {
                    Navigator.pop(context);
                    if (activeRoute == AppRoutes.settings) return;
                    Navigator.of(context).pushNamed(AppRoutes.settings);
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  context: context,
                  currentRoute: activeRoute,
                  route: '',
                  icon: LucideIcons.logOut,
                  activeIcon: LucideIcons.logOut,
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

  Widget _buildExpansionTile({
    required BuildContext context,
    required String currentRoute,
    required String title,
    required IconData icon,
    required IconData activeIcon,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    // Verificar se algum dos filhos está ativo
    final hasActiveChild = children.any((child) {
      if (child is Container) {
        final listTile = child.child;
        if (listTile is ListTile && listTile.onTap != null) {
          // Tentar extrair a rota do widget se possível
          // Por enquanto, vamos apenas verificar a expansão
        }
      }
      return false;
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasActiveChild
            ? primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(
          isExpanded ? activeIcon : icon,
          color: hasActiveChild ? primaryColor : theme.colorScheme.onSurface,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: hasActiveChild ? primaryColor : theme.colorScheme.onSurface,
            fontWeight: hasActiveChild ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        children: children,
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
    bool isSubItem = false,
  }) {
    final theme = Theme.of(context);
    final active =
        isActive ||
        (currentRoute == route && route.isNotEmpty) ||
        (route == AppRoutes.chat && currentRoute.startsWith('/chat'));

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

    // Obter contador de notificações para esta rota
    int notificationCount = 0;
    if (route.isNotEmpty && !isDestructive) {
      try {
        // Para chat, usar ChatUnreadController
        if (route == AppRoutes.chat || route.startsWith('/chat')) {
          final chatController = context.watch<ChatUnreadController>();
          notificationCount = chatController.totalUnreadCount;
        } else {
          final notificationController = context
              .watch<NotificationController>();
          notificationCount = notificationController.getCountForRoute(route);
        }
      } catch (e) {
        // Se não conseguir ler o controller, ignora
      }
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isSubItem ? 32 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(iconToShow, color: color),
            if (notificationCount > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: active ? primaryColor : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    notificationCount > 99 ? '99+' : '$notificationCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (notificationCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? primaryColor : const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  notificationCount > 99 ? '99+' : '$notificationCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
          ],
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
