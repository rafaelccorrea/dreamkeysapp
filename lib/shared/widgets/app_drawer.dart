import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/auth_service.dart';
import '../services/token_refresh_service.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/dashboard_service.dart';
import '../services/permission_service.dart';
import '../services/secure_storage_service.dart';
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
  bool _companyIsMatrix = false;

  // Dados do usuário carregados do serviço
  String? _loadedUserName;
  String? _loadedUserEmail;
  String? _loadedUserAvatar;
  bool _isLoadingProfile = false;
  String? _heroRole;
  String? _heroPhone;

  // Estado dos expansion tiles
  bool _gestaoExpanded = false;
  bool _documentosExpanded = false;
  bool _gestaoInternaExpanded = false;

  /// Lista para o seletor de empresa (Master)
  List<Company> _masterCompanies = [];
  bool _loadingMasterCompanies = false;

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
        activeRoute == AppRoutes.kanban ||
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
          _heroRole = null;
          _heroPhone = null;
        });
      }
      _fetchHeroProfileMetadata();
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
          final p = profileResponse.data!;
          setState(() {
            _syncHeroFieldsFromProfile(p);
            _loadedUserName = p.name;
            _loadedUserEmail = p.email;
            _loadedUserAvatar = p.avatar;
            debugPrint(
              '✅ [APP_DRAWER] Perfil carregado via ProfileService: ${p.name} (${p.email})',
            );
            _isLoadingProfile = false;
          });
          _loadCompaniesForMaster();
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
            final u = dashboardResponse.data!.user;
            _loadedUserName = u.name;
            _loadedUserEmail = u.email;
            _loadedUserAvatar = u.avatar;
            final rr = u.role.trim();
            _heroRole = rr.isNotEmpty ? rr : null;
            _heroPhone = null;
            debugPrint(
              '✅ [APP_DRAWER] Perfil carregado via DashboardService: ${u.name} (${u.email})',
            );
          } else {
            debugPrint(
              '❌ [APP_DRAWER] Erro ao carregar perfil (ambos os serviços falharam): ${dashboardResponse.message}',
            );
          }
          _isLoadingProfile = false;
        });
        _loadCompaniesForMaster();
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
          _companyIsMatrix = response.data?.isMatrix ?? false;
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

  void _syncHeroFieldsFromProfile(Profile p) {
    final r = p.role.trim();
    _heroRole = r.isNotEmpty ? r : null;
    final cell = p.cellphone?.trim();
    final ph = p.phone?.trim();
    _heroPhone = (cell != null && cell.isNotEmpty)
        ? cell
        : (ph != null && ph.isNotEmpty ? ph : null);
  }

  Future<void> _fetchHeroProfileMetadata() async {
    try {
      final r = await ProfileService.instance.getProfile();
      if (!mounted || !r.success || r.data == null) return;
      setState(() => _syncHeroFieldsFromProfile(r.data!));
      _loadCompaniesForMaster();
    } catch (e) {
      debugPrint('⚠️ [APP_DRAWER] Hero metadata: $e');
    }
  }

  String _formatRoleForDisplay(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) {
          final lower = w.toLowerCase();
          if (lower.isEmpty) return '';
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  String _heroDateLine() {
    return DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now());
  }

  bool get _isMasterUser {
    final r = _heroRole?.trim().toLowerCase() ?? '';
    return r == 'master';
  }

  Future<void> _loadCompaniesForMaster() async {
    if (!_isMasterUser || !mounted) return;
    setState(() => _loadingMasterCompanies = true);
    final res = await CompanyService.instance.getCompanies();
    if (!mounted) return;
    setState(() {
      _loadingMasterCompanies = false;
      _masterCompanies = res.success && res.data != null ? res.data! : [];
    });
  }

  void _openProfileDrawerHeader() {
    if (_isLoadingProfile) return;
    Navigator.pop(context);
    Navigator.of(context).pushNamed(AppRoutes.profile);
  }

  Future<void> _showCompanyPickerSheet(BuildContext parentContext) async {
    if (!_isMasterUser) return;

    if (_masterCompanies.isEmpty && !_loadingMasterCompanies) {
      await _loadCompaniesForMaster();
    }
    if (!mounted || !parentContext.mounted) return;

    if (_masterCompanies.length <= 1) {
      ScaffoldMessenger.maybeOf(parentContext)?.showSnackBar(
        SnackBar(
          content: Text(
            _masterCompanies.isEmpty
                ? 'Não foi possível carregar empresas.'
                : 'Apenas uma empresa disponível nesta conta.',
          ),
        ),
      );
      return;
    }

    final currentId = await SecureStorageService.instance.getCompanyId();
    if (!parentContext.mounted) return;

    final maxHeight = MediaQuery.sizeOf(parentContext).height * 0.42;

    await showModalBottomSheet<void>(
      context: parentContext,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(sheetContext).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Trocar de empresa',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Painel e dados seguirão o contexto selecionado.',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(sheetContext),
                      ),
                ),
              ),
              SizedBox(
                height: maxHeight,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _masterCompanies)
                      ListTile(
                        leading: Icon(
                          c.id == currentId ? Icons.check_circle_rounded : Icons.apartment_rounded,
                          color: _drawerAccentColor(sheetContext),
                        ),
                        title: Text(c.name),
                        subtitle: c.isMatrix ? const Text('Matriz') : null,
                        trailing: c.id == currentId
                            ? Text(
                                'Ativa',
                                style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: ThemeHelpers.textSecondaryColor(sheetContext),
                                    ),
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          if (!parentContext.mounted) return;
                          await _applyCompanySwitch(parentContext, c);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _applyCompanySwitch(BuildContext parentContext, Company company) async {
    final messenger = ScaffoldMessenger.maybeOf(parentContext);
    final oldId = await SecureStorageService.instance.getCompanyId();

    if (oldId == company.id) return;

    final res = await CompanyService.instance.setSelectedCompany(company.id);
    if (!parentContext.mounted) return;

    if (!res.success) {
      messenger?.showSnackBar(
        SnackBar(content: Text(res.message ?? 'Não foi possível trocar de empresa')),
      );
      return;
    }

    if (oldId != null && oldId.isNotEmpty) {
      NotificationController.instance.unsubscribeCompany(oldId);
    }
    NotificationController.instance.subscribeCompany(company.id);
    NotificationController.instance.clear();
    await NotificationController.instance.refreshUnreadCount();

    await PermissionService.instance.clearPermissionsCache();
    await ChatUnreadController.instance.reconnectForCompanyChange();

    if (mounted) {
      await _loadCompany();
      setState(() {});
    }

    if (!parentContext.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text('Empresa ativa: ${company.name}')),
    );

    Navigator.of(parentContext).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  Widget _buildCompanyBadgeForHeader(BuildContext context, ThemeData theme, Color accent) {
    if (_companyName != null && _companyName!.isNotEmpty) {
      final label =
          _companyIsMatrix ? '${_companyName!} · Matriz' : _companyName!;
      final allowPicker =
          _isMasterUser && _masterCompanies.length > 1 && !_loadingMasterCompanies;
      final chip = _buildDrawerHeroChip(
        context,
        icon: LucideIcons.building2,
        label: label,
        accent: accent,
      );
      if (!allowPicker) return chip;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCompanyPickerSheet(context),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                chip,
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_isLoadingCompany) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: accent,
        ),
      );
    }
    return const SizedBox.shrink();
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

  Color _drawerAccentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  List<Widget> _drawerAmbientHighlights(BuildContext context) {
    final accent = _drawerAccentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cool = isDark ? const Color(0xFF4F46E5) : const Color(0xFF818CF8);
    return [
      Positioned(
        top: -48,
        right: -36,
        child: IgnorePointer(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.22 : 0.14),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 140,
        left: -72,
        child: IgnorePointer(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withValues(alpha: isDark ? 0.16 : 0.09),
                  cool.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildDrawerHeroChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
        ),
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : accent.withValues(alpha: 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context, ThemeData theme, Color accent) {
    final isDark = theme.brightness == Brightness.dark;
    final cool = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final fullName = (_userName ?? 'Usuário').trim().isEmpty
        ? 'Usuário'
        : (_userName ?? 'Usuário').trim();
    final roleLabel = _formatRoleForDisplay(_heroRole);

    void openProfile() {
      _openProfileDrawerHeader();
    }

    return Material(
      color: Colors.transparent,
      child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -36,
                top: -28,
                child: IgnorePointer(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: isDark ? 0.28 : 0.18),
                          accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -50,
                bottom: -40,
                child: IgnorePointer(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          cool.withValues(alpha: isDark ? 0.2 : 0.1),
                          cool.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 12,
                  20,
                  18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.2 : 0.11),
                      accent.withValues(alpha: isDark ? 0.06 : 0.03),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color:
                          ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _isLoadingProfile ? null : openProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CONTA ATIVA',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isLoadingProfile)
                          const SizedBox(
                            width: 72,
                            height: 72,
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: cool.withValues(alpha: isDark ? 0.15 : 0.12),
                                  blurRadius: 24,
                                  spreadRadius: -4,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 33,
                              backgroundColor:
                                  ThemeHelpers.cardBackgroundColor(context),
                              backgroundImage: _userAvatar != null
                                  ? NetworkImage(_userAvatar!)
                                  : null,
                              child: _userAvatar == null
                                  ? Text(
                                      (_userName ?? 'U')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 28,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isLoadingProfile)
                                const SizedBox(
                                  height: 48,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: 160,
                                      height: 4,
                                      child: LinearProgressIndicator(),
                                    ),
                                  ),
                                )
                              else ...[
                                Text(
                                  fullName,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: ThemeHelpers.textColor(context),
                                    height: 1.05,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _userEmail ?? '—',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(context),
                                    height: 1.35,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _heroDateLine(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        ThemeHelpers.textSecondaryColor(context),
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCompanyBadgeForHeader(context, theme, accent),
                        if (roleLabel.isNotEmpty)
                          _buildDrawerHeroChip(
                            context,
                            icon: LucideIcons.briefcase,
                            label: roleLabel,
                            accent: accent,
                          ),
                        if (_heroPhone != null && _heroPhone!.isNotEmpty)
                          _buildDrawerHeroChip(
                            context,
                            icon: LucideIcons.phone,
                            label: _heroPhone!,
                            accent: accent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _isLoadingProfile ? null : openProfile,
                      child: Row(
                        children: [
                          Text(
                            'Ver perfil completo',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = _getCurrentRoute();
    final accent = _drawerAccentColor(context);

    final gestaoGroupActive =
        activeRoute == AppRoutes.properties ||
        activeRoute == AppRoutes.clients ||
        activeRoute == AppRoutes.matches ||
        activeRoute == AppRoutes.calendar ||
        activeRoute == AppRoutes.kanban ||
        activeRoute.startsWith('/clients');

    final documentosGroupActive =
        activeRoute == AppRoutes.documents ||
        activeRoute == AppRoutes.signatures ||
        activeRoute.startsWith('/documents');

    final internaGroupActive =
        activeRoute == AppRoutes.kanban ||
        activeRoute == AppRoutes.inspections ||
        activeRoute == AppRoutes.keys ||
        activeRoute.startsWith('/inspections') ||
        activeRoute.startsWith('/keys');

    return Drawer(
      backgroundColor: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: ThemeHelpers.shellBackgroundDecoration(context),
          ),
          ..._drawerAmbientHighlights(context),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDrawerHeader(context, theme, accent),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.home,
                              icon: LucideIcons.layoutDashboard,
                              activeIcon: LucideIcons.layoutDashboard,
                              title: 'Dashboard',
                              accent: accent,
                              showLeadingTile: true,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute == AppRoutes.home) return;
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  AppRoutes.home,
                                  (route) => false,
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: ThemeHelpers.borderLightColor(context)
                                  .withValues(alpha: 0.5),
                            ),
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.chat,
                              icon: LucideIcons.messageCircle,
                              activeIcon: LucideIcons.messageCircle,
                              title: 'Mensagens',
                              accent: accent,
                              showLeadingTile: true,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute == AppRoutes.chat ||
                                    activeRoute.startsWith('/chat')) {
                                  return;
                                }
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  AppRoutes.chat,
                                  (route) => false,
                                );
                              },
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: ThemeHelpers.borderLightColor(context)
                                  .withValues(alpha: 0.45),
                            ),
                            _buildExpansionTile(
                              context: context,
                              title: 'Negócios',
                              icon: LucideIcons.building2,
                              activeIcon: LucideIcons.building2,
                              isExpanded: _gestaoExpanded,
                              groupActive: gestaoGroupActive,
                              accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                            _buildExpansionTile(
                              context: context,
                              title: 'Documentos',
                              icon: LucideIcons.folder,
                              activeIcon: LucideIcons.folder,
                              isExpanded: _documentosExpanded,
                              groupActive: documentosGroupActive,
                              accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                            _buildExpansionTile(
                              context: context,
                              title: 'Interno',
                              icon: LucideIcons.briefcase,
                              activeIcon: LucideIcons.briefcase,
                              isExpanded: _gestaoInternaExpanded,
                              groupActive: internaGroupActive,
                              accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
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
                                  accent: accent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showComingSoon(context);
                                  },
                                  isSubItem: true,
                                ),
                              ],
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: ThemeHelpers.borderLightColor(context)
                                  .withValues(alpha: 0.5),
                            ),
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.settings,
                              icon: LucideIcons.settings,
                              activeIcon: LucideIcons.settings,
                              title: 'Configurações',
                              accent: accent,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute == AppRoutes.settings) return;
                                Navigator.of(context).pushNamed(AppRoutes.settings);
                              },
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: ThemeHelpers.borderLightColor(context)
                                  .withValues(alpha: 0.5),
                            ),
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: '',
                              icon: LucideIcons.logOut,
                              activeIcon: LucideIcons.logOut,
                              title: 'Sair',
                              accent: accent,
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpansionTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required IconData activeIcon,
    required bool isExpanded,
    required bool groupActive,
    required Color accent,
    required ValueChanged<bool> onExpansionChanged,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final emphasis = groupActive || isExpanded;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final tileBgIdle = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.black.withValues(alpha: 0.04);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        leading: SizedBox(
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: emphasis
                  ? LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.22),
                        accent.withValues(alpha: 0.08),
                      ],
                    )
                  : null,
              color: emphasis ? null : tileBgIdle,
            ),
            child: Center(
              child: Icon(
                isExpanded ? activeIcon : icon,
                size: 21,
                color: emphasis ? accent : secondary,
              ),
            ),
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: emphasis ? ThemeHelpers.textColor(context) : secondary,
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
            height: 1.15,
          ),
        ),
        trailing: Icon(
          isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          color: secondary,
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
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
    required Color accent,
    bool isDestructive = false,
    bool isActive = false,
    bool isSubItem = false,
    bool showLeadingTile = false,
  }) {
    final theme = Theme.of(context);
    final active =
        isActive ||
        (currentRoute == route && route.isNotEmpty) ||
        (route == AppRoutes.chat && currentRoute.startsWith('/chat'));

    final color = isDestructive
        ? theme.colorScheme.error
        : active
            ? accent
            : ThemeHelpers.textColor(context);

    final iconToShow = active ? activeIcon : icon;

    int notificationCount = 0;
    if (route.isNotEmpty && !isDestructive) {
      try {
        if (route == AppRoutes.chat || route.startsWith('/chat')) {
          final chatController = context.watch<ChatUnreadController>();
          notificationCount = chatController.totalUnreadCount;
        } else {
          final notificationController =
              context.watch<NotificationController>();
          notificationCount = notificationController.getCountForRoute(route);
        }
      } catch (e) {
        // Provider ausente em alguns contextos
      }
    }

    final borderColor =
        active ? accent.withValues(alpha: 0.35) : Colors.transparent;

    final isDark = theme.brightness == Brightness.dark;
    final tileBgIdle = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.black.withValues(alpha: 0.04);

    Widget leadingIcon = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Icon(iconToShow, size: 22, color: color),
        if (notificationCount > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: active ? accent : const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  width: 2,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                notificationCount > 99 ? '99+' : '$notificationCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );

    if (showLeadingTile) {
      leadingIcon = SizedBox(
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: active
                ? LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.28),
                      accent.withValues(alpha: 0.09),
                    ],
                  )
                : null,
            color: active
                ? null
                : tileBgIdle,
          ),
          child: Center(child: leadingIcon),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isSubItem ? 4 : 2,
        vertical: isSubItem ? 2 : 3,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: active ? 1 : 0),
            ),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isSubItem ? 10 : 12,
                vertical: showLeadingTile ? 10 : 6,
              ),
              horizontalTitleGap: 12,
              minLeadingWidth: showLeadingTile ? 44 : 28,
              leading: leadingIcon,
              title: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
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
        if (appNavigatorKey.currentState != null) {
          appNavigatorKey.currentState!.pushNamedAndRemoveUntil(
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
          if (appNavigatorKey.currentState != null) {
            appNavigatorKey.currentState!.pushNamedAndRemoveUntil(
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
