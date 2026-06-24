import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_action_sheets.dart';
import '../widgets/approval_property_card.dart';

/// Tela de **Fila de Aprovação de Imóveis**.
///
/// Identidade visual **flush** alinhada ao DNA do app:
/// - Padding página `_kPagePadH=16 / top=10 / bottom=88`, conteúdo encostado nas
///   margens, sem glows/painéis.
/// - Greeting com ícone gradiente + eyebrow `letterSpacing 2.2` + título grande;
///   alerta de recusados como chip estático (sem animação).
/// - **Navegação em abas flush com sublinhado** (mesmo padrão de Documentos/
///   Chaves) — indicador na cor da fila ativa, filete inferior de largura total.
/// - Cabeçalho de painel com ícone tonal achatado + eyebrow com bolinha.
/// - Itens são **linhas flush** (`ApprovalPropertyCard`) — thumbnail grande com
///   código abaixo, sem faixa lateral; aprovar/recusar no próprio card para quem
///   tem permissão nas filas de disponibilidade/publicação.
class PropertyApprovalsPage extends StatefulWidget {
  const PropertyApprovalsPage({super.key});

  @override
  State<PropertyApprovalsPage> createState() => _PropertyApprovalsPageState();
}

enum _Tab { mine, ownerAuth, availability, publication, rejected }

class _PropertyApprovalsPageState extends State<PropertyApprovalsPage> {
  static const double _kSectionGap = 12;
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const int _kRejectedPageSize = 10;

  late final ModuleAccessService _moduleAccess = ModuleAccessService.instance;
  late final bool _hasView;

  // Estado por aba.
  bool _loadingMine = false;
  String? _errorMine;
  MyPendingResponse _myPending = MyPendingResponse.empty;

  bool _loadingAvailability = false;
  String? _errorAvailability;
  List<Property> _pendingAvailability = const [];

  bool _loadingPublication = false;
  String? _errorPublication;
  List<Property> _pendingPublication = const [];

  bool _loadingOwner = false;
  String? _errorOwner;
  List<Property> _pendingOwner = const [];

  bool _loadingRejectedAvail = false;
  bool _loadingRejectedPub = false;
  String? _errorRejected;
  RejectedListResponse _rejectedAvail = RejectedListResponse.empty;
  RejectedListResponse _rejectedPub = RejectedListResponse.empty;
  RejectedCounts _rejectedCounts = RejectedCounts.zero;

  _Tab _activeTab = _Tab.mine;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _hasView = _moduleAccess.hasPermission(AppPermissions.propertyView);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _refreshAll();
  }

  Future<void> _refreshAll() {
    return Future.wait([
      _loadMine(),
      if (_hasView) ...[
        _loadAvailability(),
        _loadPublication(),
        _loadOwnerAuth(),
        _loadRejected(),
      ],
    ]);
  }

  ApprovalListFilters _filters() => ApprovalListFilters(search: _appliedSearch);

  void _selectTab(_Tab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _refreshAll();
    });
  }

  // ─── Loaders ───────────────────────────────────────────────────────────

  Future<void> _loadMine() async {
    setState(() {
      _loadingMine = true;
      _errorMine = null;
    });
    final res = await PropertyApprovalService.instance.getMyPending(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingMine = false;
      if (res.success && res.data != null) {
        _myPending = res.data!;
      } else {
        _errorMine = res.message ?? 'Erro ao carregar suas pendências';
      }
    });
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _loadingAvailability = true;
      _errorAvailability = null;
    });
    final res =
        await PropertyApprovalService.instance.getPendingAvailability(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingAvailability = false;
      if (res.success && res.data != null) {
        _pendingAvailability = res.data!;
      } else {
        _errorAvailability =
            res.message ?? 'Erro ao carregar fila de disponibilidade';
      }
    });
  }

  Future<void> _loadPublication() async {
    setState(() {
      _loadingPublication = true;
      _errorPublication = null;
    });
    final res = await PropertyApprovalService.instance.getPendingPublication(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingPublication = false;
      if (res.success && res.data != null) {
        _pendingPublication = res.data!;
      } else {
        _errorPublication =
            res.message ?? 'Erro ao carregar fila de publicação';
      }
    });
  }

  Future<void> _loadOwnerAuth() async {
    setState(() {
      _loadingOwner = true;
      _errorOwner = null;
    });
    final res = await PropertyApprovalService.instance
        .getPendingOwnerAuthorization(filters: _filters());
    if (!mounted) return;
    setState(() {
      _loadingOwner = false;
      if (res.success && res.data != null) {
        _pendingOwner = res.data!;
      } else {
        _errorOwner = res.message ?? 'Erro ao carregar autorizações';
      }
    });
  }

  Future<void> _loadRejected({int page = 1}) async {
    setState(() {
      _loadingRejectedAvail = true;
      _loadingRejectedPub = true;
      _errorRejected = null;
    });
    final svc = PropertyApprovalService.instance;
    final results = await Future.wait([
      svc.getRejectedAvailability(
        filters: _filters(),
        page: page,
        limit: _kRejectedPageSize,
      ),
      svc.getRejectedPublication(
        filters: _filters(),
        page: page,
        limit: _kRejectedPageSize,
      ),
      svc.getRejectedCounts(filters: _filters()),
    ]);
    if (!mounted) return;
    setState(() {
      _loadingRejectedAvail = false;
      _loadingRejectedPub = false;
      final r0 = results[0];
      final r1 = results[1];
      final r2 = results[2];
      if (r0.success && r0.data != null) {
        _rejectedAvail = r0.data! as RejectedListResponse;
      } else if (r0.message != null) {
        _errorRejected = r0.message;
      }
      if (r1.success && r1.data != null) {
        _rejectedPub = r1.data! as RejectedListResponse;
      } else if (r1.message != null) {
        _errorRejected ??= r1.message;
      }
      if (r2.success && r2.data != null) {
        _rejectedCounts = r2.data! as RejectedCounts;
      }
    });
  }

  void _openDetails(Property p) {
    Navigator.of(context).pushNamed(AppRoutes.propertyDetails(p.id));
  }

  // ─── Ações de aprovar/recusar direto no card (gated por permissão) ────────

  bool get _canApproveAvailability => _moduleAccess
      .hasPermission(AppPermissions.propertyApproveAvailability);
  bool get _canRejectAvailability =>
      _moduleAccess.hasPermission(AppPermissions.propertyRejectAvailability);
  bool get _canApprovePublication => _moduleAccess
      .hasPermission(AppPermissions.propertyApprovePublication);
  bool get _canRejectPublication =>
      _moduleAccess.hasPermission(AppPermissions.propertyRejectPublication);

  void _actionSnack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  /// Aprova o card conforme a fila. Retorna `true` em sucesso (para o card
  /// encerrar o estado de carregamento). Atualiza as listas no fim.
  Future<bool> _approveCard(Property p, ApprovalQueueKind kind) async {
    final svc = PropertyApprovalService.instance;
    final isPub = kind == ApprovalQueueKind.pendingPublication;
    final res = isPub
        ? await svc.approvePublication(p.id, applyWatermark: null)
        : await svc.approveAvailability(p.id, applyWatermark: false);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack(
        isPub
            ? 'Publicação aprovada — imóvel já está no site.'
            : 'Disponibilidade aprovada.',
        ok: true,
      );
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao aprovar.');
    return false;
  }

  /// Coleta o motivo (obrigatório) e recusa o card conforme a fila.
  Future<bool> _rejectCard(Property p, ApprovalQueueKind kind) async {
    final isPub = kind == ApprovalQueueKind.pendingPublication;
    final reason = await showRejectReasonSheet(
      context: context,
      title: isPub ? 'Recusar publicação no site' : 'Recusar disponibilidade',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return false;
    final svc = PropertyApprovalService.instance;
    final res = isPub
        ? await svc.rejectPublication(p.id, reason: reason)
        : await svc.rejectAvailability(p.id, reason: reason);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Imóvel recusado. Responsável foi notificado.', ok: true);
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao recusar.');
    return false;
  }

  // ─── Helpers visuais ──────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Cor coerente da aba ativa — usada no ícone/eyebrow do cabeçalho do painel
  /// pra cada fila ter sua identidade (não "tudo vermelho").
  Color _activeTabColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (_activeTab) {
      case _Tab.availability:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case _Tab.publication:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case _Tab.ownerAuth:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      case _Tab.rejected:
        return isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error;
      case _Tab.mine:
        return _accentColor(context);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aprovações',
      currentBottomNavIndex: 1,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: _accentColor(context),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kPagePadTop,
                      _kPagePadH,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kSectionGap,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
                    child: _buildActivePanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Greeting (estilo `_buildGreeting` do dashboard) ───────────────────

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final pendingTotal = _pendingTotal();
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  isDark
                      ? AppColors.primary.primaryDarkDarkMode
                      : AppColors.primary.primaryDark,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? accent.withValues(alpha: 0.30)
                      : accent.withValues(alpha: 0.18),
                  blurRadius: isDark ? 14 : 11,
                  offset: Offset(0, isDark ? 8 : 4),
                  spreadRadius: isDark ? 0 : -1,
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.shieldCheck,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FILA DE APROVAÇÃO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasView
                      ? (pendingTotal == 0
                          ? 'Tudo em dia por aqui'
                          : '$pendingTotal ${pendingTotal == 1 ? 'imóvel aguarda' : 'imóveis aguardam'} aprovação')
                      : 'Acompanhe seus imóveis na fila',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                if (_rejectedCounts.total > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: danger.withValues(alpha: isDark ? 0.16 : 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color:
                              danger.withValues(alpha: isDark ? 0.4 : 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.alertTriangle,
                              size: 12, color: danger),
                          const SizedBox(width: 6),
                          Text(
                            '${_rejectedCounts.total} recusado${_rejectedCounts.total == 1 ? '' : 's'} aguardando reenvio',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: danger,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'Liberação para a operação e para o site',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _pendingTotal() {
    return _myPending.total +
        _pendingAvailability.length +
        _pendingPublication.length +
        _pendingOwner.length;
  }

  // ─── Search field ─────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final hasText = _searchController.text.trim().isNotEmpty;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    OutlineInputBorder fieldBorder(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: _searchController,
      onChanged: (v) {
        _onSearchChanged(v);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: hasText
            ? Color.alphaBlend(
                accent.withValues(alpha: isDark ? 0.08 : 0.04), fieldFill)
            : fieldFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        hintText: 'Buscar por código, título, proprietário…',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w500,
        ),
        // Ícone integrado (sem caixa) — mudo quando vazio, accent quando busca.
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(
            LucideIcons.search,
            size: 20,
            color: hasText
                ? accent
                : ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 38),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                splashRadius: 18,
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
              ),
        border: fieldBorder(ThemeHelpers.borderLightColor(context), 1),
        enabledBorder: fieldBorder(
          hasText
              ? accent.withValues(alpha: isDark ? 0.5 : 0.38)
              : ThemeHelpers.borderLightColor(context),
          hasText ? 1.4 : 1,
        ),
        focusedBorder:
            fieldBorder(accent.withValues(alpha: isDark ? 0.6 : 0.45), 1.5),
      ),
    );
  }

  // ─── Tabs horizontais (pills com gradiente) ───────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final ok = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final warn = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final purple = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;

    final tabs = <_TabSpec>[
      _TabSpec(
        tab: _Tab.mine,
        icon: LucideIcons.user,
        label: 'Meus',
        count: _myPending.total,
        accentColor: accent,
      ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.availability,
          icon: LucideIcons.checkCircle2,
          label: 'Disponibilidade',
          count: _pendingAvailability.length,
          accentColor: ok,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.publication,
          icon: LucideIcons.globe,
          label: 'Publicação',
          count: _pendingPublication.length,
          accentColor: warn,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.ownerAuth,
          icon: LucideIcons.fileSignature,
          label: 'Proprietário',
          count: _pendingOwner.length,
          accentColor: purple,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.rejected,
          icon: LucideIcons.alertTriangle,
          label: 'Recusados',
          count: _rejectedCounts.total,
          accentColor: danger,
        ),
    ];

    // Barra de abas **flush** com sublinhado — o mesmo padrão de navegação do
    // resto do app (Documentos, Chaves). Sem pills flutuantes: filete inferior
    // de largura total e indicador na cor da fila ativa.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 4),
        child: Row(
          children: [
            for (final t in tabs)
              _FlushTab(
                spec: t,
                selected: _activeTab == t.tab,
                onTap: () => _selectTab(t.tab),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Seção ativa (sem painel encapsulando) ────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final isLoading = _isCurrentTabLoading();
    final hasError = _currentTabError() != null;
    final hasContent = _currentTabHasContent();

    Widget child;
    if (isLoading && !hasContent) {
      child = _buildSkeletonList();
    } else if (hasError && !hasContent) {
      child = _buildPanelError();
    } else if (!hasContent) {
      child = _buildEmptyState();
    } else {
      child = _buildTabBody();
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta() {
    switch (_activeTab) {
      case _Tab.mine:
        return (
          icon: LucideIcons.user,
          eyebrow: 'SUAS PENDÊNCIAS',
          title: 'Meus imóveis',
          hint: 'O que está aguardando você ou seu cliente.',
        );
      case _Tab.ownerAuth:
        return (
          icon: LucideIcons.fileSignature,
          eyebrow: 'PROPRIETÁRIO',
          title: 'Aguardando autorização',
          hint: 'Imóveis pendentes da assinatura do proprietário.',
        );
      case _Tab.availability:
        return (
          icon: LucideIcons.checkCircle2,
          eyebrow: 'DISPONIBILIDADE',
          title: 'Liberação para a operação',
          hint: 'Imóveis aguardando aprovação para ficar disponíveis.',
        );
      case _Tab.publication:
        return (
          icon: LucideIcons.globe,
          eyebrow: 'PUBLICAÇÃO',
          title: 'Liberação para o site',
          hint: 'Aguardando aprovação para o portal público.',
        );
      case _Tab.rejected:
        return (
          icon: LucideIcons.alertTriangle,
          eyebrow: 'RECUSADOS',
          title: 'Aguardando ajustes',
          hint: 'Imóveis recusados que precisam de correção.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabColor = _activeTabColor(context);
    final meta = _panelMeta();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tabColor.withValues(alpha: isDark ? 0.20 : 0.12),
          ),
          child: Icon(meta.icon, color: tabColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tabColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tabColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    meta.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tabColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isCurrentTabLoading() {
    switch (_activeTab) {
      case _Tab.mine:
        return _loadingMine;
      case _Tab.ownerAuth:
        return _loadingOwner;
      case _Tab.availability:
        return _loadingAvailability;
      case _Tab.publication:
        return _loadingPublication;
      case _Tab.rejected:
        return _loadingRejectedAvail || _loadingRejectedPub;
    }
  }

  String? _currentTabError() {
    switch (_activeTab) {
      case _Tab.mine:
        return _errorMine;
      case _Tab.ownerAuth:
        return _errorOwner;
      case _Tab.availability:
        return _errorAvailability;
      case _Tab.publication:
        return _errorPublication;
      case _Tab.rejected:
        return _errorRejected;
    }
  }

  bool _currentTabHasContent() {
    switch (_activeTab) {
      case _Tab.mine:
        return _myPending.total > 0;
      case _Tab.ownerAuth:
        return _pendingOwner.isNotEmpty;
      case _Tab.availability:
        return _pendingAvailability.isNotEmpty;
      case _Tab.publication:
        return _pendingPublication.isNotEmpty;
      case _Tab.rejected:
        return _rejectedAvail.data.isNotEmpty ||
            _rejectedPub.data.isNotEmpty;
    }
  }

  Widget _buildTabBody() {
    final List<Widget> nodes = [];

    void addList(List<Property> list, ApprovalQueueKind kind) {
      // Ações só nas filas de aprovação (disponibilidade/publicação) e somente
      // para quem tem a permissão correspondente.
      final canApprove = kind == ApprovalQueueKind.pendingAvailability
          ? _canApproveAvailability
          : kind == ApprovalQueueKind.pendingPublication
              ? _canApprovePublication
              : false;
      final canReject = kind == ApprovalQueueKind.pendingAvailability
          ? _canRejectAvailability
          : kind == ApprovalQueueKind.pendingPublication
              ? _canRejectPublication
              : false;
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        nodes.add(
          ApprovalPropertyCard(
            property: p,
            kind: kind,
            onOpenDetails: () => _openDetails(p),
            canApprove: canApprove,
            canReject: canReject,
            onApprove: canApprove ? () => _approveCard(p, kind) : null,
            onReject: canReject ? () => _rejectCard(p, kind) : null,
          )
              .animate(key: ValueKey('card-${p.id}-$kind'))
              .fadeIn(
                delay: Duration(milliseconds: 40 * i),
                duration: 220.ms,
              ),
        );
      }
    }

    void addSubsection(String label, IconData icon, int count) {
      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 14));
      nodes.add(_PanelSubsectionHeader(label: label, icon: icon, count: count));
      nodes.add(const SizedBox(height: 8));
    }

    switch (_activeTab) {
      case _Tab.mine:
        if (_myPending.pendingAvailability.isNotEmpty) {
          addSubsection('Aguardando disponibilidade',
              LucideIcons.checkCircle2, _myPending.pendingAvailability.length);
          addList(_myPending.pendingAvailability,
              ApprovalQueueKind.myAvailability);
        }
        if (_myPending.pendingOwnerAuthorization.isNotEmpty) {
          addSubsection('Aguardando proprietário', LucideIcons.fileSignature,
              _myPending.pendingOwnerAuthorization.length);
          addList(_myPending.pendingOwnerAuthorization,
              ApprovalQueueKind.myOwnerAuth);
        }
        if (_myPending.pendingPublication.isNotEmpty) {
          addSubsection('Aguardando publicação', LucideIcons.globe,
              _myPending.pendingPublication.length);
          addList(_myPending.pendingPublication,
              ApprovalQueueKind.myPublication);
        }
        break;
      case _Tab.ownerAuth:
        addList(_pendingOwner, ApprovalQueueKind.pendingOwnerAuth);
        break;
      case _Tab.availability:
        addList(_pendingAvailability, ApprovalQueueKind.pendingAvailability);
        break;
      case _Tab.publication:
        addList(_pendingPublication, ApprovalQueueKind.pendingPublication);
        break;
      case _Tab.rejected:
        if (_rejectedAvail.data.isNotEmpty) {
          addSubsection('Disponibilidade recusada',
              LucideIcons.alertTriangle, _rejectedAvail.total);
          addList(
              _rejectedAvail.data, ApprovalQueueKind.rejectedAvailability);
        }
        if (_rejectedPub.data.isNotEmpty) {
          addSubsection('Publicação recusada', LucideIcons.alertTriangle,
              _rejectedPub.total);
          addList(_rejectedPub.data, ApprovalQueueKind.rejectedPublication);
        }
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildSkeletonList() {
    // Espelha a linha flush real (faixa + thumbnail + texto + filete),
    // não um card arredondado — coerência no estado de carregamento.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(4, (i) => const _ApprovalRowSkeleton()),
    );
  }

  Widget _buildPanelError() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            _currentTabError() ?? 'Erro ao carregar',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _refreshAll,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final meta = _emptyMeta();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Icon(meta.icon, color: accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            meta.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String title, String body}) _emptyMeta() {
    switch (_activeTab) {
      case _Tab.mine:
        return (
          icon: LucideIcons.partyPopper,
          title: 'Tudo em dia por aqui',
          body:
              'Nenhum dos seus imóveis está aguardando aprovação no momento.',
        );
      case _Tab.ownerAuth:
        return (
          icon: LucideIcons.fileSignature,
          title: 'Sem autorizações pendentes',
          body:
              'Quando o proprietário ainda não tiver assinado, o imóvel aparece aqui.',
        );
      case _Tab.availability:
        return (
          icon: LucideIcons.partyPopper,
          title: 'Nada na fila de disponibilidade',
          body:
              'Imóveis aguardando aprovação para a operação aparecem aqui.',
        );
      case _Tab.publication:
        return (
          icon: LucideIcons.globe,
          title: 'Nada na fila de publicação',
          body:
              'Imóveis aguardando entrar no site público aparecem aqui.',
        );
      case _Tab.rejected:
        return (
          icon: LucideIcons.shieldCheck,
          title: 'Nenhum imóvel recusado',
          body:
              'Quando algum imóvel for recusado, ele fica listado aqui para revisão.',
        );
    }
  }
}

// ─── Subwidgets internos ────────────────────────────────────────────────

/// Placeholder de carregamento que reproduz a linha flush real
/// (`ApprovalPropertyCard`): thumbnail 72 com código abaixo, texto e filete.
class _ApprovalRowSkeleton extends StatelessWidget {
  const _ApprovalRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                SkeletonBox(width: 72, height: 72, borderRadius: 14),
                const SizedBox(height: 7),
                SkeletonText(width: 60, height: 12, borderRadius: 999),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 96, height: 18, borderRadius: 999),
                  const SizedBox(height: 9),
                  SkeletonText(width: double.infinity, height: 14),
                  const SizedBox(height: 6),
                  SkeletonText(width: 140, height: 12),
                  const SizedBox(height: 10),
                  SkeletonText(width: 120, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  final _Tab tab;
  final IconData icon;
  final String label;
  final int count;
  final Color accentColor;

  _TabSpec({
    required this.tab,
    required this.icon,
    required this.label,
    required this.count,
    required this.accentColor,
  });
}

/// Aba **flush** com sublinhado (padrão de navegação do app). Sem fundo/pill:
/// rótulo + contagem, indicador na cor da fila quando ativa.
class _FlushTab extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = spec.accentColor;
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(spec.icon, size: 16, color: fg),
                  const SizedBox(width: 7),
                  Text(
                    spec.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w900 : FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (spec.count > 0) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: selected ? 0.16 : 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        spec.count > 99 ? '99+' : '${spec.count}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected
                              ? tone
                              : ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Indicador (sublinhado) — anima a cor, altura estável p/ não pular.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelSubsectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  const _PanelSubsectionHeader({
    required this.label,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon,
            size: 14,
            color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

