import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/module_access_service.dart';
import '../services/auth_service.dart';
import '../services/token_refresh_service.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/dashboard_service.dart';
import '../services/permission_service.dart';
import '../services/secure_storage_service.dart';
import '../utils/avatar_url_resolver.dart';
import 'skeleton_box.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/chat/controllers/chat_unread_controller.dart';

/// Drawer (menu lateral) — itens alinhados ao menu **visível** do web
/// (`imobx-front/src/components/layout/Drawer.tsx`): sem Chat, Matches,
/// Checklists, Documentos, Vistorias/Chaves no menu (no web estão `hidden`),
/// sem entradas “em breve”.
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
  bool _companyIsMatrix = false;

  // Dados do usuário carregados do serviço
  String? _loadedUserName;
  String? _loadedUserEmail;
  String? _loadedUserAvatar;
  String? _heroRole;
  String? _heroPhone;

  // Estado dos expansion tiles (alinhado a grupos do drawer web)
  bool _imoveisExpanded = false;
  bool _vendasCrmExpanded = false;
  bool _colaboradoresExpanded = false;
  bool _suporteExpanded = false;
  bool _integracoesExpanded = false;
  bool _configExpanded = false;

  /// Lista para o seletor de empresa (Master)
  List<Company> _masterCompanies = [];

  /// Único estado de loading do drawer.
  ///
  /// Antes existiam 3 flags independentes (`_isLoadingCompany`,
  /// `_isLoadingProfile`, `_loadingMasterCompanies`) — cada seção
  /// mostrava seu próprio spinner pequeno. Resultado: o usuário via
  /// avatar carregando, depois empresa carregando, depois badge piscando…
  /// um por um. Visualmente "ridículo".
  ///
  /// Agora unificamos: enquanto `_isInitializing == true`, o drawer
  /// inteiro mostra skeleton (header + body). Vira `false` somente quando
  /// **todas** as cargas em paralelo terminam.
  bool _isInitializing = true;

  /// Sinaliza troca de empresa em curso — também ativa o skeleton geral
  /// (mesma estética de "carregando tudo de novo").
  bool _isSwitchingCompany = false;
  String? _switchingCompanyLabel;

  @override
  void initState() {
    super.initState();
    // Reage a mudanças de permissões/empresa do `ModuleAccessService`
    // (login, troca de empresa, refresh) — itens do drawer com gating
    // (ex.: "Aprovações") aparecem/somem ao vivo, sem precisar restart.
    ModuleAccessService.instance.addListener(_onModuleAccessChanged);
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkActiveRoutes();
    });
  }

  void _onModuleAccessChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onModuleAccessChanged);
    super.dispose();
  }

  /// Inicialização paralela — dispara perfil, empresa e permissões
  /// simultaneamente, e só desliga o skeleton quando todos terminam.
  /// Cada `_silent*` é tolerante a falhas: nunca lança, só atualiza
  /// estado interno.
  ///
  /// Carregar permissões aqui é defensivo — se o usuário entrou direto
  /// pelo `LoginPage` (sem passar pelo `SplashPage` que chama
  /// `initialize()`), o `ModuleAccessService` em memória estaria vazio
  /// e itens com gating (ex.: "Aprovações") só apareceriam após restart.
  Future<void> _bootstrap() async {
    final futures = <Future<void>>[
      _loadCompany(),
      _loadProfile(),
      _ensureModuleAccessReady(),
    ];
    await Future.wait(futures);

    // Lista de empresas master é necessária pra mostrar o picker.
    // Roda em paralelo só DEPOIS que o profile terminou (precisamos saber
    // se é master), mas não bloqueamos o `_isInitializing` por isso —
    // se demorar, o drawer já abre e o picker é habilitado depois.
    if (_isMasterUser) {
      // ignore: unawaited_futures
      _loadCompaniesForMaster();
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// Garante `ModuleAccessService` populado quando o drawer monta. Se já
  /// está com permissões carregadas (boot via splash), só refresca em
  /// background; senão, espera o fetch terminar pra evitar item de menu
  /// "piscando" depois da primeira renderização.
  Future<void> _ensureModuleAccessReady() async {
    final svc = ModuleAccessService.instance;
    if (svc.userPermissions == null) {
      await svc.initialize();
    } else {
      // Refresh assíncrono em background — listener no
      // `_onModuleAccessChanged` re-renderiza se algo mudar.
      // ignore: unawaited_futures
      svc.refreshPermissions();
    }
  }

  void _checkActiveRoutes() {
    if (!mounted) return;
    final activeRoute = _getCurrentRoute();

    bool expandImoveis = false;
    bool expandVendasCrm = false;
    bool expandColaboradores = false;

    if (activeRoute == AppRoutes.properties ||
        activeRoute == AppRoutes.propertyApprovals ||
        activeRoute.startsWith('/properties') ||
        activeRoute.startsWith('/condominiums') ||
        activeRoute.startsWith('/developments')) {
      expandImoveis = true;
    }

    if (activeRoute == AppRoutes.kanban ||
        activeRoute == AppRoutes.kanbanSubtasks ||
        activeRoute.startsWith('/kanban/task') ||
        activeRoute == AppRoutes.clients ||
        activeRoute.startsWith('/clients') ||
        activeRoute.startsWith('/whatsapp') ||
        activeRoute == AppRoutes.saleForms ||
        activeRoute.startsWith('/proposals') ||
        activeRoute.startsWith('/rental-forms')) {
      expandVendasCrm = true;
    }

    if (activeRoute == AppRoutes.users ||
        activeRoute == AppRoutes.teams ||
        activeRoute == AppRoutes.workspace ||
        activeRoute.startsWith('/check-in')) {
      expandColaboradores = true;
    }

    final expandSuporte =
        activeRoute.startsWith('/tickets') || activeRoute == AppRoutes.help;

    final expandIntegracoes = activeRoute.startsWith('/integrations');

    final expandConfig =
        activeRoute == AppRoutes.settings ||
        activeRoute == AppRoutes.mySite ||
        activeRoute == AppRoutes.bioLink;

    if (expandImoveis ||
        expandVendasCrm ||
        expandColaboradores ||
        expandSuporte ||
        expandIntegracoes ||
        expandConfig) {
      setState(() {
        if (expandImoveis) _imoveisExpanded = true;
        if (expandVendasCrm) _vendasCrmExpanded = true;
        if (expandColaboradores) _colaboradoresExpanded = true;
        if (expandSuporte) _suporteExpanded = true;
        if (expandIntegracoes) _integracoesExpanded = true;
        if (expandConfig) _configExpanded = true;
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

  /// Carrega dados do perfil sem manipular `_isInitializing` — quem
  /// controla isso é o `_bootstrap()`. Tolerante a falha (nunca rethrow).
  Future<void> _loadProfile() async {
    // Se já temos os dados completos via parâmetros, fetch só metadata
    if (widget.userName != null &&
        widget.userName!.isNotEmpty &&
        widget.userEmail != null &&
        widget.userEmail!.isNotEmpty) {
      if (_loadedUserName != null || _loadedUserEmail != null) {
        if (mounted) {
          setState(() {
            _loadedUserName = null;
            _loadedUserEmail = null;
            _loadedUserAvatar = null;
            _heroRole = null;
            _heroPhone = null;
          });
        }
      }
      await _fetchHeroProfileMetadata();
      return;
    }

    if (_loadedUserName != null && _loadedUserEmail != null) {
      return;
    }

    try {
      // Tentar primeiro o ProfileService
      final profileResponse = await ProfileService.instance.getProfile();

      if (profileResponse.success && profileResponse.data != null) {
        if (mounted) {
          final p = profileResponse.data!;
          setState(() {
            _syncHeroFieldsFromProfile(p);
            _loadedUserName = p.name;
            _loadedUserEmail = p.email;
            _loadedUserAvatar = p.avatar;
          });
        }
        return;
      }

      // Fallback: DashboardService
      final dashboardResponse = await DashboardService.instance
          .getUserDashboard();
      if (mounted &&
          dashboardResponse.success &&
          dashboardResponse.data != null) {
        final u = dashboardResponse.data!.user;
        setState(() {
          _loadedUserName = u.name;
          _loadedUserEmail = u.email;
          _loadedUserAvatar = u.avatar;
          final rr = u.role.trim();
          _heroRole = rr.isNotEmpty ? rr : null;
          _heroPhone = null;
        });
      }
    } catch (e) {
      debugPrint('❌ [APP_DRAWER] Erro ao carregar perfil: $e');
    }
  }

  Future<void> _loadCompany() async {
    try {
      final response = await CompanyService.instance.getSelectedCompany();
      if (mounted) {
        setState(() {
          _companyName = response.data?.name;
          _companyIsMatrix = response.data?.isMatrix ?? false;
        });
      }
    } catch (e) {
      debugPrint('❌ [APP_DRAWER] Erro ao carregar empresa: $e');
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

  /// Carrega as empresas do usuário para o seletor. O backend escopa a lista
  /// por usuário (master vê todas; admin/gestor/corretor só as suas), então o
  /// picker vale para QUALQUER papel multi-empresa — paridade com o
  /// CompanySelector do header web. Para master pré-carregamos no init; para
  /// os demais a carga é lazy (ao tocar no chip da empresa).
  Future<void> _loadCompaniesForMaster() async {
    if (!mounted) return;
    final res = await CompanyService.instance.getCompanies();
    if (!mounted) return;
    setState(() {
      _masterCompanies = res.success && res.data != null ? res.data! : [];
    });
  }

  void _openProfileDrawerHeader() {
    if (_isInitializing) return;
    Navigator.pop(context);
    Navigator.of(context).pushNamed(AppRoutes.profile);
  }

  Future<void> _showCompanyPickerSheet(BuildContext parentContext) async {
    if (_masterCompanies.isEmpty) {
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

    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _CompanyPickerSheet(
          companies: _masterCompanies,
          currentId: currentId,
          accent: _drawerAccentColor(sheetContext),
          onPick: (c) async {
            Navigator.pop(sheetContext);
            if (!parentContext.mounted) return;
            await _applyCompanySwitch(parentContext, c);
          },
        );
      },
    );
  }

  Future<void> _applyCompanySwitch(
    BuildContext parentContext,
    Company company,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(parentContext);
    final oldId = await SecureStorageService.instance.getCompanyId();

    if (oldId == company.id) return;

    // Liga o skeleton geral imediatamente: o drawer inteiro vira
    // skeleton com a faixa "Trocando para X…" enquanto roda toda a
    // cadeia de invalidações e refetches em background.
    if (mounted) {
      setState(() {
        _isSwitchingCompany = true;
        _switchingCompanyLabel = 'Trocando para ${company.name}…';
      });
    }

    final res = await CompanyService.instance.setSelectedCompany(company.id);
    if (!parentContext.mounted) return;

    if (!res.success) {
      if (mounted) {
        setState(() {
          _isSwitchingCompany = false;
          _switchingCompanyLabel = null;
        });
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Não foi possível trocar de empresa'),
        ),
      );
      return;
    }

    // Roda invalidações em paralelo (antes eram sequenciais).
    if (oldId != null && oldId.isNotEmpty) {
      NotificationController.instance.unsubscribeCompany(oldId);
    }
    NotificationController.instance.subscribeCompany(company.id);
    NotificationController.instance.clear();

    // 1) Limpa o cache local de permissões (storage) ANTES de
    //    `refreshPermissions` — assim a próxima leitura via `_getMyPermissions`
    //    pega da API com o `X-Company-ID` da empresa nova.
    await PermissionService.instance.clearPermissionsCache();

    // 2) Roda em paralelo: refetch real das permissões da nova empresa,
    //    notification badge, chat reconnect e dados da empresa exibidos
    //    no header. O `refreshPermissions` notifica listeners do
    //    `ModuleAccessService` automaticamente — itens do drawer com
    //    gating (ex.: "Aprovações") ressurgem/somem na hora.
    await Future.wait<void>([
      ModuleAccessService.instance.refreshPermissions(),
      NotificationController.instance.refreshUnreadCount(),
      ChatUnreadController.instance.reconnectForCompanyChange(),
      _loadCompany(),
    ]);

    if (!parentContext.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text('Empresa ativa: ${company.name}')),
    );

    // Importante: NÃO desligamos `_isSwitchingCompany` aqui — o drawer
    // permanece em skeleton até a Home assumir, evitando "flash" do
    // conteúdo antigo entre a troca e a navegação.
    Navigator.of(
      parentContext,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Widget _buildCompanyBadgeForHeader(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    if (_companyName != null && _companyName!.isNotEmpty) {
      final label = _companyIsMatrix
          ? '${_companyName!} · Matriz'
          : _companyName!;
      // Master: só é clicável quando há 2+ empresas (lista pré-carregada).
      // Demais papéis: sempre clicável — a lista é carregada ao tocar e, se
      // houver só uma empresa, o sheet avisa (paridade com o web).
      final allowPicker =
          _isMasterUser ? _masterCompanies.length > 1 : true;
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
                // Flexible: o chip encolhe (o rótulo já tem ellipsis) para o
                // chevron caber na largura do drawer — sem overflow com nomes
                // de empresa longos.
                Flexible(child: chip),
                Icon(Icons.arrow_drop_down_rounded, size: 22, color: accent),
              ],
            ),
          ),
        ),
      );
    }
    // Sem company carregada: nada (skeleton geral cobre essa fase).
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

  Widget _buildDrawerHeader(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
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
                    color: ThemeHelpers.borderColor(
                      context,
                    ).withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _isInitializing ? null : openProfile,
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
                            // Skeleton geral (`_isInitializing`) cobre essa
                            // fase — quando renderizamos o header real, os
                            // dados já estão disponíveis.
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
                                    color: cool.withValues(
                                      alpha: isDark ? 0.15 : 0.12,
                                    ),
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
                                    ? NetworkImage(
                                        AvatarUrlResolver.resolve(
                                              _userAvatar,
                                            ) ??
                                            _userAvatar!,
                                      )
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
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                      height: 1.35,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _heroDateLine(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
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
                    onTap: _isInitializing ? null : openProfile,
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

  /// Skeleton geral do drawer — header (avatar + linhas + chips) e body
  /// (linhas de menu) animados em pulso suave. Usado tanto na inicialização
  /// quanto na troca de empresa, mantendo a estrutura visual estável.
  Widget _buildDrawerSkeleton(
    BuildContext context,
    ThemeData theme,
    Color accent, {
    String? switchingMessage,
  }) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: ThemeHelpers.shellBackgroundDecoration(context),
          ),
          ..._drawerAmbientHighlights(context),
          SafeArea(
            child: _DrawerSkeletonShell(
              accent: accent,
              switchingMessage: switchingMessage,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = _getCurrentRoute();
    final accent = _drawerAccentColor(context);

    // Skeleton geral: cobre tanto o boot inicial quanto a transição
    // de empresa. Substitui os 3 spinners pequenos antigos por uma
    // estrutura única, sincronizada e estável visualmente.
    if (_isInitializing || _isSwitchingCompany) {
      return _buildDrawerSkeleton(
        context,
        theme,
        accent,
        switchingMessage: _isSwitchingCompany ? _switchingCompanyLabel : null,
      );
    }

    final imoveisGroupActive =
        activeRoute == AppRoutes.properties ||
        activeRoute == AppRoutes.propertyApprovals ||
        activeRoute.startsWith('/properties');

    final vendasCrmGroupActive =
        activeRoute == AppRoutes.kanban ||
        activeRoute == AppRoutes.kanbanSubtasks ||
        activeRoute.startsWith('/kanban/task') ||
        activeRoute == AppRoutes.clients ||
        activeRoute.startsWith('/clients') ||
        activeRoute.startsWith('/whatsapp') ||
        activeRoute == AppRoutes.saleForms ||
        activeRoute.startsWith('/proposals') ||
        activeRoute.startsWith('/rental-forms');

    final suporteGroupActive =
        activeRoute.startsWith('/tickets') || activeRoute == AppRoutes.help;

    final integracoesGroupActive = activeRoute.startsWith('/integrations');

    final configGroupActive =
        activeRoute == AppRoutes.settings ||
        activeRoute == AppRoutes.mySite ||
        activeRoute == AppRoutes.bioLink;

    // Paridade com `Drawer.tsx` do web: item "Aprovações" só aparece se o
    // usuário tem `view`, `create`, `approve_*` ou `manage_approval_settings`
    // — com bypass admin/master/manager via `hasAnyPermission`.
    final canSeeApprovalsMenu = ModuleAccessService.instance.hasAnyPermission(
      AppPermissions.approvalQueueMenu,
    );

    final canSeeProperties =
        ModuleAccessService.instance.hasCompanyModule('property_management') &&
        ModuleAccessService.instance.hasPermission('property:view');
    final canSeeKanban =
        ModuleAccessService.instance.hasCompanyModule('kanban_management') &&
        ModuleAccessService.instance.hasPermission('kanban:view');
    final canSeeClients =
        ModuleAccessService.instance.hasCompanyModule('client_management') &&
        ModuleAccessService.instance.hasPermission('client:view');
    final canSeeCalendar =
        ModuleAccessService.instance.hasCompanyModule('calendar_management') &&
        ModuleAccessService.instance.hasPermission('calendar:view');

    final canSeeNotes =
        ModuleAccessService.instance.hasCompanyModule('notes') &&
        ModuleAccessService.instance.hasPermission('note:view');
    final canSeeProposals =
        ModuleAccessService.instance.hasCompanyModule('sale_forms') &&
        (ModuleAccessService.instance.hasPermission('proposal:view') ||
            ModuleAccessService.instance.hasPermission('proposal:view_team') ||
            ModuleAccessService.instance.hasPermission('proposal:view_all'));
    final canSeeSaleForms =
        ModuleAccessService.instance.hasCompanyModule('sale_forms') &&
        ModuleAccessService.instance.hasAnyPermission(
          AppPermissions.saleFormMenu,
        );
    // Comissões: módulo da empresa + permissão de visualização (corretor vê só
    // as próprias; master/admin/manager têm bypass no ModuleAccessService).
    // Colaboradores → Usuários (drawer item).
    // Paridade com web: `user:view` AND (`create` OR `update` OR `delete`),
    // com bypass admin/master/manager via `hasAnyPermission`.
    final canSeeUsers =
        ModuleAccessService.instance.hasCompanyModule('user_management') &&
        ModuleAccessService.instance.hasPermission(AppPermissions.userView) &&
        ModuleAccessService.instance.hasAnyPermission(
          AppPermissions.userManageMenu,
        );
    // Colaboradores → Equipes (drawer item).
    final canSeeTeams =
        ModuleAccessService.instance.hasCompanyModule('team_management') &&
        ModuleAccessService.instance.hasPermission(AppPermissions.teamView);
    /// Visibilidade do item "Check-in": liberado pra master/admin/manager
    /// (gestores veem tudo) ou para quem tem `check_in:do` / `check_in:view`.
    /// O backend bate as permissões finais; aqui é só gating de menu.
    final checkInRole =
        ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';
    final isCheckInPrivileged =
        checkInRole == 'master' ||
        checkInRole == 'admin' ||
        checkInRole == 'manager';
    final canSeeCheckIn =
        isCheckInPrivileged ||
        ModuleAccessService.instance.hasPermission(AppPermissions.checkInDo) ||
        ModuleAccessService.instance.hasPermission(AppPermissions.checkInView);

    // Colaboradores agrupa Usuários, Equipes e Check-in (posição do web).
    final canSeeWorkspace = canSeeUsers || canSeeTeams || canSeeCheckIn;

    // Condomínios & Empreendimentos (gate do web: property_management +
    // condominium:view para ambos).
    final canSeeCondominiums =
        ModuleAccessService.instance.hasCompanyModule('property_management') &&
        ModuleAccessService.instance.hasPermission('condominium:view');

    // OCULTOS do menu (rotas vivas), espelhando o menu do web: Visitas,
    // MCMV, Metas, Checklists, Patrimônio, Locações/Seguros/Crédito/Régua,
    // Gamificação/Prêmios, Zezin, Automações e analytics avançado.

    // WhatsApp inbox (paridade com /whatsapp do web: módulo api_integrations
    // + ANY-OF whatsapp:view / whatsapp:view_messages).
    final canSeeWhatsapp =
        ModuleAccessService.instance.hasCompanyModule('api_integrations') &&
        (ModuleAccessService.instance.hasPermission('whatsapp:view') ||
            ModuleAccessService.instance
                .hasPermission('whatsapp:view_messages'));

    // SDR com IA (/sdr) e Comissões (/commissions): ocultos do menu por
    // decisão de produto — rotas continuam vivas.

    // Central de Integrações (any-of dos módulos/permissões do web).
    final canSeeIntegrations = (ModuleAccessService.instance
                .hasCompanyModule('api_integrations') ||
            ModuleAccessService.instance
                .hasCompanyModule('third_party_integrations') ||
            ModuleAccessService.instance
                .hasCompanyModule('lead_distribution')) &&
        ModuleAccessService.instance.hasAnyPermission(const [
          'whatsapp:view',
          'whatsapp:manage_config',
          'meta_campaign:manage_config',
          'grupo_zap:manage_config',
          'lead_distribution:manage_config',
          'kanban:manage_users',
        ]);

    // Meu Site + Link in Bio (módulo public_site_hosting).
    final canSeePublicSite =
        ModuleAccessService.instance.hasCompanyModule('public_site_hosting') &&
        ModuleAccessService.instance.hasPermission('public_site:view');

    // Análise Multicanal (único analytics visível no menu — como no web).
    final canSeeMultichannel = ModuleAccessService.instance
            .hasCompanyModule('public_site_analytics') &&
        ModuleAccessService.instance.hasPermission('public_analytics:view');

    // Fichas de Locação (única superfície de locações visível — mora em
    // Vendas & CRM como no menu web).
    final canSeeRentalForms =
        ModuleAccessService.instance.hasCompanyModule('rental_management') &&
        ModuleAccessService.instance.hasPermission('rental_form:view');

    // Suporte — Central de Ajuda é aberta a todos; tickets exigem criar/ver.
    final canSeeTickets =
        ModuleAccessService.instance.hasPermission('ticket:create') ||
        ModuleAccessService.instance.hasPermission('ticket:view');

    final showImoveisGroup =
        canSeeProperties || canSeeApprovalsMenu || canSeeCondominiums;
    final showVendasCrmGroup =
        canSeeKanban ||
        canSeeClients ||
        canSeeWhatsapp ||
        canSeeSaleForms ||
        canSeeProposals ||
        canSeeRentalForms;
    final showIntegracoesGroup = canSeeIntegrations;

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
                          if (canSeeMultichannel)
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.analyticsMultichannel,
                              icon: LucideIcons.radar,
                              activeIcon: LucideIcons.radar,
                              title: 'Análise Multicanal',
                              accent: accent,
                              showLeadingTile: true,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute ==
                                    AppRoutes.analyticsMultichannel) {
                                  return;
                                }
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.analyticsMultichannel);
                              },
                            ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: ThemeHelpers.borderLightColor(
                              context,
                            ).withValues(alpha: 0.5),
                          ),
                          if (showVendasCrmGroup) ...[
                            _buildExpansionTile(
                              context: context,
                              title: 'Vendas & CRM',
                              icon: LucideIcons.target,
                              activeIcon: LucideIcons.target,
                              isExpanded: _vendasCrmExpanded,
                              groupActive: vendasCrmGroupActive,
                              accent: accent,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _vendasCrmExpanded = expanded;
                                });
                              },
                              children: [
                                if (canSeeWhatsapp)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.whatsapp,
                                    icon: LucideIcons.messageCircle,
                                    activeIcon: LucideIcons.messageCircle,
                                    title: 'WhatsApp',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/whatsapp',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.whatsapp) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.whatsapp);
                                    },
                                    isSubItem: true,
                                  ),
                                // SDR com IA: oculto do menu (rota /sdr viva).
                                if (canSeeKanban)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.kanban,
                                    icon: LucideIcons.layoutGrid,
                                    activeIcon: LucideIcons.layoutGrid,
                                    title: 'CRM',
                                    accent: accent,
                                    isActive:
                                        activeRoute == AppRoutes.kanban ||
                                        activeRoute.startsWith('/kanban/task'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.kanban ||
                                          activeRoute.startsWith(
                                            '/kanban/task',
                                          )) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
                                        AppRoutes.kanban,
                                        (route) => false,
                                      );
                                    },
                                    isSubItem: true,
                                  ),
                                // Fichas moram em Vendas & CRM (posição do
                                // menu web). Visitas e MCMV: ocultos como no
                                // web (rotas /visits e /mcmv/* vivas).
                                if (canSeeSaleForms)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.saleForms,
                                    icon: LucideIcons.handshake,
                                    activeIcon: LucideIcons.handshake,
                                    title: 'Fichas de venda',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.saleForms) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.saleForms);
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeProposals)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.proposals,
                                    icon: LucideIcons.fileSignature,
                                    activeIcon: LucideIcons.fileSignature,
                                    title: 'Fichas de proposta',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.proposals) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.proposals);
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeRentalForms)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.rentalForms,
                                    icon: LucideIcons.clipboardList,
                                    activeIcon: LucideIcons.clipboardList,
                                    title: 'Fichas de locação',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/rental-forms',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute ==
                                          AppRoutes.rentalForms) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.rentalForms);
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeClients)
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
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
                                        AppRoutes.clients,
                                        (route) => false,
                                      );
                                    },
                                    isSubItem: true,
                                  ),
                              ],
                            ),
                          ],
                          if (showImoveisGroup) ...[
                            _buildExpansionTile(
                              context: context,
                              title: 'Imóveis',
                              icon: LucideIcons.home,
                              activeIcon: LucideIcons.home,
                              isExpanded: _imoveisExpanded,
                              groupActive: imoveisGroupActive,
                              accent: accent,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _imoveisExpanded = expanded;
                                });
                              },
                              children: [
                                if (canSeeProperties)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.properties,
                                    icon: LucideIcons.building2,
                                    activeIcon: LucideIcons.building2,
                                    title: 'Propriedades',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.properties) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
                                        AppRoutes.properties,
                                        (route) => false,
                                      );
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeCondominiums) ...[
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.condominiums,
                                    icon: LucideIcons.building,
                                    activeIcon: LucideIcons.building,
                                    title: 'Condomínios',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/condominiums',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute ==
                                          AppRoutes.condominiums) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.condominiums);
                                    },
                                    isSubItem: true,
                                  ),
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.developments,
                                    icon: LucideIcons.blocks,
                                    activeIcon: LucideIcons.blocks,
                                    title: 'Empreendimentos',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/developments',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute ==
                                          AppRoutes.developments) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.developments);
                                    },
                                    isSubItem: true,
                                  ),
                                ],
                                if (canSeeApprovalsMenu)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.propertyApprovals,
                                    icon: LucideIcons.shieldCheck,
                                    activeIcon: LucideIcons.shieldCheck,
                                    title: 'Aprovações',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute ==
                                          AppRoutes.propertyApprovals) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.propertyApprovals);
                                    },
                                    isSubItem: true,
                                  ),
                              ],
                            ),
                          ],
                          if (canSeeWorkspace)
                            _buildExpansionTile(
                              context: context,
                              title: 'Colaboradores',
                              icon: LucideIcons.users2,
                              activeIcon: LucideIcons.users2,
                              isExpanded: _colaboradoresExpanded,
                              groupActive:
                                  activeRoute == AppRoutes.users ||
                                  activeRoute == AppRoutes.teams ||
                                  activeRoute == AppRoutes.workspace ||
                                  activeRoute.startsWith('/check-in'),
                              accent: accent,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _colaboradoresExpanded = expanded;
                                });
                              },
                              children: [
                                if (canSeeUsers)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.users,
                                    icon: LucideIcons.users,
                                    activeIcon: LucideIcons.users,
                                    title: 'Usuários',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.users) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.users);
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeTeams)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.teams,
                                    icon: LucideIcons.users2,
                                    activeIcon: LucideIcons.users2,
                                    title: 'Equipes',
                                    accent: accent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.teams) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.teams);
                                    },
                                    isSubItem: true,
                                  ),
                                if (canSeeCheckIn)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.checkIn,
                                    icon: LucideIcons.mapPin,
                                    activeIcon: LucideIcons.mapPin,
                                    title: 'Check-in',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/check-in',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute == AppRoutes.checkIn) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.checkIn);
                                    },
                                    isSubItem: true,
                                  ),
                              ],
                            ),
                          if (canSeeCalendar)
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.calendar,
                              icon: LucideIcons.calendar,
                              activeIcon: LucideIcons.calendar,
                              title: 'Calendário',
                              accent: accent,
                              showLeadingTile: true,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute == AppRoutes.calendar) return;
                                Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.calendar);
                              },
                            ),
                          if (canSeeNotes)
                            _buildDrawerItem(
                              context: context,
                              currentRoute: activeRoute,
                              route: AppRoutes.notes,
                              icon: LucideIcons.scrollText,
                              activeIcon: LucideIcons.scrollText,
                              title: 'Anotações',
                              accent: accent,
                              showLeadingTile: true,
                              onTap: () {
                                Navigator.pop(context);
                                if (activeRoute == AppRoutes.notes) return;
                                Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.notes);
                              },
                            ),
                          // Comissões: oculto do menu (rota /commissions viva).
                          // Produtividade (Checklists/Patrimônio/Metas) e
                          // Operacional (Locações/Seguros/Crédito/Régua):
                          // OCULTOS — não estão visíveis no menu do web.
                          // Rotas continuam vivas; Fichas de Locação mora em
                          // Vendas & CRM (posição do web).
                          _buildExpansionTile(
                            context: context,
                            title: 'Suporte',
                            icon: LucideIcons.lifeBuoy,
                            activeIcon: LucideIcons.lifeBuoy,
                            isExpanded: _suporteExpanded,
                            groupActive: suporteGroupActive,
                            accent: accent,
                            onExpansionChanged: (expanded) {
                              setState(() {
                                _suporteExpanded = expanded;
                              });
                            },
                            children: [
                              _buildDrawerItem(
                                context: context,
                                currentRoute: activeRoute,
                                route: AppRoutes.help,
                                icon: LucideIcons.circleHelp,
                                activeIcon: LucideIcons.circleHelp,
                                title: 'Central de Ajuda',
                                accent: accent,
                                onTap: () {
                                  Navigator.pop(context);
                                  if (activeRoute == AppRoutes.help) return;
                                  Navigator.of(
                                    context,
                                  ).pushNamed(AppRoutes.help);
                                },
                                isSubItem: true,
                              ),
                              if (canSeeTickets)
                                _buildDrawerItem(
                                  context: context,
                                  currentRoute: activeRoute,
                                  route: AppRoutes.tickets,
                                  icon: LucideIcons.lifeBuoy,
                                  activeIcon: LucideIcons.lifeBuoy,
                                  title: 'Meus tickets',
                                  accent: accent,
                                  isActive: activeRoute.startsWith('/tickets'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (activeRoute == AppRoutes.tickets) {
                                      return;
                                    }
                                    Navigator.of(
                                      context,
                                    ).pushNamed(AppRoutes.tickets);
                                  },
                                  isSubItem: true,
                                ),
                            ],
                          ),
                          if (showIntegracoesGroup) ...[
                            _buildExpansionTile(
                              context: context,
                              title: 'Integrações',
                              icon: LucideIcons.plugZap,
                              activeIcon: LucideIcons.plugZap,
                              isExpanded: _integracoesExpanded,
                              groupActive: integracoesGroupActive,
                              accent: accent,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _integracoesExpanded = expanded;
                                });
                              },
                              children: [
                                if (canSeeIntegrations)
                                  _buildDrawerItem(
                                    context: context,
                                    currentRoute: activeRoute,
                                    route: AppRoutes.integrations,
                                    icon: LucideIcons.plugZap,
                                    activeIcon: LucideIcons.plugZap,
                                    title: 'Central de Integrações',
                                    accent: accent,
                                    isActive: activeRoute.startsWith(
                                      '/integrations',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (activeRoute ==
                                          AppRoutes.integrations) {
                                        return;
                                      }
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.integrations);
                                    },
                                    isSubItem: true,
                                  ),
                                // Meu Site e Link in Bio moram no grupo
                                // Configurações (posição do menu web).
                              ],
                            ),
                          ],
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: ThemeHelpers.borderLightColor(
                              context,
                            ).withValues(alpha: 0.5),
                          ),
                          // Configurações como grupo (menu web): Meu Site,
                          // Link in Bio e Preferências do app.
                          _buildExpansionTile(
                            context: context,
                            title: 'Configurações',
                            icon: LucideIcons.settings,
                            activeIcon: LucideIcons.settings,
                            isExpanded: _configExpanded,
                            groupActive: configGroupActive,
                            accent: accent,
                            onExpansionChanged: (expanded) {
                              setState(() {
                                _configExpanded = expanded;
                              });
                            },
                            children: [
                              if (canSeePublicSite) ...[
                                _buildDrawerItem(
                                  context: context,
                                  currentRoute: activeRoute,
                                  route: AppRoutes.mySite,
                                  icon: LucideIcons.globe,
                                  activeIcon: LucideIcons.globe,
                                  title: 'Meu Site',
                                  accent: accent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (activeRoute == AppRoutes.mySite) {
                                      return;
                                    }
                                    Navigator.of(
                                      context,
                                    ).pushNamed(AppRoutes.mySite);
                                  },
                                  isSubItem: true,
                                ),
                                _buildDrawerItem(
                                  context: context,
                                  currentRoute: activeRoute,
                                  route: AppRoutes.bioLink,
                                  icon: LucideIcons.link,
                                  activeIcon: LucideIcons.link,
                                  title: 'Link in Bio',
                                  accent: accent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (activeRoute == AppRoutes.bioLink) {
                                      return;
                                    }
                                    Navigator.of(
                                      context,
                                    ).pushNamed(AppRoutes.bioLink);
                                  },
                                  isSubItem: true,
                                ),
                              ],
                              _buildDrawerItem(
                                context: context,
                                currentRoute: activeRoute,
                                route: AppRoutes.settings,
                                icon: LucideIcons.slidersHorizontal,
                                activeIcon: LucideIcons.slidersHorizontal,
                                title: 'Preferências',
                                accent: accent,
                                onTap: () {
                                  Navigator.pop(context);
                                  if (activeRoute == AppRoutes.settings) {
                                    return;
                                  }
                                  Navigator.of(
                                    context,
                                  ).pushNamed(AppRoutes.settings);
                                },
                                isSubItem: true,
                              ),
                            ],
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: ThemeHelpers.borderLightColor(
                              context,
                            ).withValues(alpha: 0.5),
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
            fontSize: 13,
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
          final notificationController = context
              .watch<NotificationController>();
          notificationCount = notificationController.getCountForRoute(route);
        }
      } catch (e) {
        // Provider ausente em alguns contextos
      }
    }

    final borderColor = active
        ? accent.withValues(alpha: 0.35)
        : Colors.transparent;

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
            color: active ? null : tileBgIdle,
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
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
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
        content: const Text(
          'Sai da sessão neste aparelho. Se já ativou Face ID ou impressão digital, '
          'pode voltar a entrar assim na próxima vez (ou com email e senha).',
        ),
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

/// Sheet premium de troca de empresa.
///
/// - Header editorial (eyebrow + título grande + subtítulo).
/// - Busca embutida (aparece só com 6+ empresas) para não poluir
///   quando o usuário tem 2-3 contas.
/// - Tiles fluidas: monograma colorido, nome, badge "Matriz", e um
///   chip "ATIVA" quando é o contexto atual.
class _CompanyPickerSheet extends StatefulWidget {
  const _CompanyPickerSheet({
    required this.companies,
    required this.currentId,
    required this.accent,
    required this.onPick,
  });

  final List<Company> companies;
  final String? currentId;
  final Color accent;
  final void Function(Company company) onPick;

  @override
  State<_CompanyPickerSheet> createState() => _CompanyPickerSheetState();
}

class _CompanyPickerSheetState extends State<_CompanyPickerSheet>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Paleta determinística por nome — cada empresa ganha um tom único
  /// no monograma, evitando o mar de "chip único" e ajudando o
  /// reconhecimento visual quando há muitas contas.
  Color _monogramColor(String name) {
    const palette = [
      Color(0xFF6366F1), // indigo
      Color(0xFF22C55E), // green
      Color(0xFFEA580C), // orange
      Color(0xFF06B6D4), // cyan
      Color(0xFFA855F7), // purple
      Color(0xFFF59E0B), // amber
      Color(0xFFEC4899), // pink
      Color(0xFF14B8A6), // teal
    ];
    final code = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[code % palette.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Company? _findCurrent() {
    if (widget.currentId == null) return null;
    for (final c in widget.companies) {
      if (c.id == widget.currentId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final viewport = MediaQuery.sizeOf(context).height;
    final cardBg = ThemeHelpers.cardBackgroundColor(context);
    final accent = widget.accent;

    final current = _findCurrent();
    final others = widget.companies
        .where((c) => c.id != widget.currentId)
        .toList();
    final filteredOthers = _query.isEmpty
        ? others
        : others
              .where(
                (c) =>
                    c.name.toLowerCase().contains(_query.toLowerCase().trim()),
              )
              .toList();

    final showSearch = others.length >= 6;
    final matrixCount = widget.companies.where((c) => c.isMatrix).length;
    final totalModules = widget.companies
        .map((c) => c.availableModules.length)
        .fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 24),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Container(
          constraints: BoxConstraints(maxHeight: viewport * 0.86),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border(
              top: BorderSide(
                color: accent.withValues(alpha: isDark ? 0.4 : 0.25),
                width: 1.4,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                blurRadius: 32,
                offset: const Offset(0, -8),
                spreadRadius: -8,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                // Decoração de gradient sutil no topo do sheet — dá
                // sensação de "luz vinda da empresa ativa" sem ser
                // chamativo. Pintada por baixo do conteúdo.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 200,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: isDark ? 0.12 : 0.06),
                            accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle premium accent
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.5),
                              accent,
                              accent.withValues(alpha: 0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),

                    // Header
                    _buildHeader(
                      theme,
                      isDark,
                      accent,
                      matrixCount,
                      totalModules,
                    ),

                    // Search (só com 6+ empresas)
                    if (showSearch) _buildSearch(theme, isDark, accent),

                    // Conteúdo scrollável: empresa ativa + lista de outras
                    Flexible(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          // EMPRESA ATIVA (em destaque)
                          if (current != null) ...[
                            _buildSectionLabel('EMPRESA ATIVA', accent),
                            const SizedBox(height: 10),
                            _CompanyActiveCard(
                              company: current,
                              accent: accent,
                              monogramColor: _monogramColor(current.name),
                              initials: _initials(current.name),
                              pulse: _pulse,
                            ),
                            const SizedBox(height: 22),
                          ],

                          // OUTRAS EMPRESAS DISPONÍVEIS
                          if (filteredOthers.isNotEmpty) ...[
                            _buildSectionLabel(
                              _query.isEmpty
                                  ? 'OUTRAS EMPRESAS'
                                  : 'RESULTADOS · ${filteredOthers.length}',
                              accent,
                            ),
                            const SizedBox(height: 8),
                            for (final c in filteredOthers)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _CompanyOptionTile(
                                  company: c,
                                  accent: accent,
                                  monogramColor: _monogramColor(c.name),
                                  initials: _initials(c.name),
                                  onTap: () => widget.onPick(c),
                                ),
                              ),
                          ] else if (_query.isNotEmpty)
                            _buildEmpty(theme, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(
    ThemeData theme,
    bool isDark,
    Color accent,
    int matrixCount,
    int totalModules,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow com bolinha pulsante (live indicator)
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: _pulse.value),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: _pulse.value * 0.6,
                              ),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WORKSPACE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.6,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Título grande
                Text(
                  'Trocar de empresa',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.02,
                    letterSpacing: -0.6,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 8),
                // Stats line — texto rico
                _buildStatsLine(theme, matrixCount, totalModules),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Botão fechar premium (não chip pequeno)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsLine(ThemeData theme, int matrixCount, int totalModules) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = widget.companies.length;
    final parts = <String>[
      '$total ${total == 1 ? "empresa" : "empresas"}',
      if (matrixCount > 0)
        '$matrixCount ${matrixCount == 1 ? "matriz" : "matrizes"}',
      if (totalModules > 0)
        '$totalModules ${totalModules == 1 ? "módulo" : "módulos"}',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Text(
              '·',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary.withValues(alpha: 0.6),
                fontWeight: FontWeight.w900,
              ),
            ),
          Text(
            parts[i],
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearch(ThemeData theme, bool isDark, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _query.isNotEmpty
                ? accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderLightColor(context),
            width: _query.isNotEmpty ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: _query.isNotEmpty
                  ? accent
                  : ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar empresa…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              InkWell(
                onTap: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: accent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color accent) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(width: 4, height: 12, color: accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 36,
              color: ThemeHelpers.textSecondaryColor(
                context,
              ).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Nenhuma empresa encontrada',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tente outro termo de busca',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(
                  context,
                ).withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card destacado da empresa ATUAL — aparece em bloco separado no topo,
/// fora da lista das outras opções, pra deixar claro qual está ativa.
class _CompanyActiveCard extends StatelessWidget {
  const _CompanyActiveCard({
    required this.company,
    required this.accent,
    required this.monogramColor,
    required this.initials,
    required this.pulse,
  });

  final Company company;
  final Color accent;
  final Color monogramColor;
  final String initials;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modulesCount = company.availableModules.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.16 : 0.10),
            accent.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.5 : 0.36),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Monograma maior (52px) com sombra premium accent
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  monogramColor,
                  Color.lerp(monogramColor, Colors.black, 0.22) ??
                      monogramColor,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: monogramColor.withValues(alpha: 0.42),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: pulse,
                      builder: (_, __) => Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFF22C55E,
                          ).withValues(alpha: pulse.value),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: pulse.value * 0.6),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CONECTADO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF22C55E),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  company.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (company.isMatrix)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: accent.withValues(alpha: 0.18),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.36),
                          ),
                        ),
                        child: Text(
                          'MATRIZ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: accent,
                            letterSpacing: 0.8,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    Text(
                      modulesCount > 0
                          ? '$modulesCount ${modulesCount == 1 ? "módulo" : "módulos"}'
                          : 'Sem módulos',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile clicável de empresa não-ativa — clean, com microinteração ao tap.
class _CompanyOptionTile extends StatelessWidget {
  const _CompanyOptionTile({
    required this.company,
    required this.accent,
    required this.monogramColor,
    required this.initials,
    required this.onTap,
  });

  final Company company;
  final Color accent;
  final Color monogramColor;
  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modulesCount = company.availableModules.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: monogramColor.withValues(alpha: 0.10),
        highlightColor: monogramColor.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.transparent,
            border: Border.all(
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: isDark ? 0.5 : 0.6),
            ),
          ),
          child: Row(
            children: [
              // Monograma 44×44 — menor que o ativo (52) pra estabelecer
              // hierarquia visual clara entre "ativa" e "outras"
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      monogramColor.withValues(alpha: 0.95),
                      monogramColor.withValues(alpha: 0.78),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: monogramColor.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      company.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (company.isMatrix) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: monogramColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Matriz',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: monogramColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '·',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(
                                context,
                              ).withValues(alpha: 0.5),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            modulesCount > 0
                                ? '$modulesCount ${modulesCount == 1 ? "módulo" : "módulos"}'
                                : 'Sem módulos',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Indicador de ação clicável — círculo accent sutil com seta
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                  ),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esqueleto editorial do drawer — pulsa suavemente. Reproduz a estrutura
/// real (header com avatar + nome + chips, depois menu) para que a
/// transição para o conteúdo real seja imperceptível visualmente.
///
/// Mostra também uma faixa "Trocando para X..." durante a troca de empresa.
/// Skeleton **minimalista** do drawer — usa o `SkeletonBox` shared (mesmo
/// shimmer das outras telas do app) para um carregamento discreto e
/// coerente, no light e no dark.
///
/// Sem pulses sólidos, sem chips ruidosas: silhueta enxuta do hero
/// (eyebrow + avatar + linhas de identidade) + uma única linha de chip
/// (badge da empresa) + lista compacta de itens de menu.
class _DrawerSkeletonShell extends StatelessWidget {
  const _DrawerSkeletonShell({required this.accent, this.switchingMessage});

  final Color accent;
  final String? switchingMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final switchMsg = switchingMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Hero compacto ──────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            switchMsg != null && switchMsg.isNotEmpty ? 14 : 18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 90, height: 9, borderRadius: 999),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SkeletonBox(width: 64, height: 64, borderRadius: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: double.infinity,
                          height: 16,
                          borderRadius: 6,
                        ),
                        const SizedBox(height: 7),
                        SkeletonBox(width: 150, height: 11, borderRadius: 4),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 90, height: 9, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SkeletonBox(width: 130, height: 24, borderRadius: 999),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 70, height: 24, borderRadius: 999),
                ],
              ),
            ],
          ),
        ),

        // ─── Banner fininho de "trocando empresa" ───────────────────────
        if (switchMsg != null && switchMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.28 : 0.20),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      switchMsg,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ─── Divider quase invisível ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(
              context,
            ).withValues(alpha: 0.5),
          ),
        ),

        // ─── Itens do menu — silhueta enxuta ────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: 7,
            itemBuilder: (_, i) {
              // Larguras com ritmo orgânico (sem repetição estridente).
              const widths = [148.0, 124.0, 168.0, 110.0, 156.0, 132.0, 142.0];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SkeletonBox(width: 22, height: 22, borderRadius: 7),
                    const SizedBox(width: 14),
                    SkeletonBox(
                      width: widths[i % widths.length],
                      height: 11,
                      borderRadius: 4,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
