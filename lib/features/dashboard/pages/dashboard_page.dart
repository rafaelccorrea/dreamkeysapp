import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/services/dashboard_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/minimal_body_chrome.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../notifications/widgets/notification_center.dart';
import '../widgets/dashboard_filters_drawer.dart';

// Formatters globais
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

final _numberFormatter = NumberFormat.decimalPattern('pt_BR');

/// Tela principal do aplicativo (Dashboard)
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// Ritmo vertical mais curto + mais leitura horizontal (estilo app).
  static const double _kSectionGap = 11;
  static const double _kPagePadH = 20;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kStatsHScrollMaxW = 532;
  static const double _kTwoColMinW = 520;
  static const double _kPerfActivityRowMinW = 640;

  bool _isLoading = true;
  DashboardResponse? _dashboardData;
  String? _errorMessage;
  DashboardFilters _filters = DashboardFilters.defaultFilters();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await DashboardService.instance.getUserDashboard(
        dateRange: _filters.dateRange ?? '30d',
        compareWith: _filters.compareWith ?? 'previous_period',
        metric: _filters.metric ?? 'all',
        startDate: _filters.startDate,
        endDate: _filters.endDate,
        activitiesLimit: _filters.activitiesLimit,
        appointmentsLimit: _filters.appointmentsLimit,
      );

      if (response.success && response.data != null) {
        if (mounted) {
          setState(() {
            _dashboardData = response.data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                response.message ?? 'Erro ao carregar dados do dashboard';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [DASHBOARD] Erro ao carregar dados: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  void _showFiltersDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => DashboardFiltersDrawer(
        initialFilters: _filters,
        onFiltersChanged: (newFilters) {
          setState(() {
            _filters = newFilters;
          });
          _loadDashboardData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Intellisys',
      currentBottomNavIndex: 0,
      userName: _dashboardData?.user.name,
      userEmail: _dashboardData?.user.email,
      userAvatar: _dashboardData?.user.avatar,
      actions: [
        const NotificationCenter(compactToolbar: true),
        ChromeToolbarIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filtros',
          onPressed: () => _showFiltersDialog(context),
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              color: _dashboardAccentColor(context),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ..._dashboardAmbientHighlights(context),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _kPagePadH,
                              _kPagePadTop,
                              _kPagePadH,
                              _kPagePadBottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            _buildGreeting(context, theme),
                            SizedBox(height: _kSectionGap + 2),
                            _buildStatsCards(context, theme),
                            if (_dashboardData != null) ...[
                              SizedBox(height: _kSectionGap),
                              LayoutBuilder(
                                builder: (context, c) {
                                  if (c.maxWidth < _kPerfActivityRowMinW) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildPerformanceCard(context, theme),
                                        SizedBox(height: _kSectionGap),
                                        _buildActivitiesSection(context, theme),
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 12,
                                        child: _buildPerformanceCard(context, theme),
                                      ),
                                      SizedBox(width: _kSectionGap),
                                      Expanded(
                                        flex: 10,
                                        child: _buildActivitiesSection(context, theme),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              SizedBox(height: _kSectionGap),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth >= _kTwoColMinW;
                                  final goals = _buildMonthlyGoalsSection(context, theme);
                                  final conversions = _buildConversionMetrics(context, theme);
                                  if (!isWide) {
                                    return Column(
                                      children: [
                                        goals,
                                        SizedBox(height: _kSectionGap),
                                        conversions,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: goals),
                                      SizedBox(width: _kSectionGap),
                                      Expanded(child: conversions),
                                    ],
                                  );
                                },
                              ),
                              if (_dashboardData!.gamification.achievements.isNotEmpty) ...[
                                SizedBox(height: _kSectionGap),
                                _buildAchievementsSection(context, theme),
                              ],
                              SizedBox(height: _kSectionGap),
                              LayoutBuilder(
                                builder: (context, c) {
                                  if (c.maxWidth < _kTwoColMinW) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildRecentActivities(context, theme),
                                        SizedBox(height: _kSectionGap),
                                        _buildUpcomingAppointments(context, theme),
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: _buildRecentActivities(context, theme)),
                                      SizedBox(width: _kSectionGap),
                                      Expanded(child: _buildUpcomingAppointments(context, theme)),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
                },
              ),
            ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton do cabeçalho
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(
                      width: 200,
                      height: 24,
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                    SkeletonText(
                      width: 180,
                      height: 16,
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                    SkeletonText(width: 150, height: 14),
                  ],
                ),
              ),
              SkeletonBox(width: 48, height: 48, borderRadius: 24),
            ],
          ),
          const SizedBox(height: 32),

          // Skeleton do card de performance
          SkeletonCard(
            height: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  width: 180,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(
                            width: 100,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                          SkeletonText(width: 80, height: 32),
                        ],
                      ),
                    ),
                    SkeletonBox(width: 60, height: 60, borderRadius: 30),
                  ],
                ),
                const SizedBox(height: 16),
                SkeletonText(
                  width: double.infinity,
                  height: 8,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Skeleton dos cards de estatísticas
          SkeletonText(
            width: 120,
            height: 20,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          Row(
            children: [
              Expanded(
                child: SkeletonCard(
                  height: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 12),
                      const SizedBox(height: 12),
                      SkeletonText(width: 80, height: 24),
                      const SizedBox(height: 4),
                      SkeletonText(width: 60, height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SkeletonCard(
                  height: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 12),
                      const SizedBox(height: 12),
                      SkeletonText(width: 80, height: 24),
                      const SizedBox(height: 4),
                      SkeletonText(width: 60, height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SkeletonCard(
                  height: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 12),
                      const SizedBox(height: 12),
                      SkeletonText(width: 80, height: 24),
                      const SizedBox(height: 4),
                      SkeletonText(width: 60, height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SkeletonCard(
                  height: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 12),
                      const SizedBox(height: 12),
                      SkeletonText(width: 80, height: 24),
                      const SizedBox(height: 4),
                      SkeletonText(width: 60, height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Skeleton da seção de atividades
          SkeletonText(
            width: 120,
            height: 20,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          SkeletonList(itemCount: 3, itemHeight: 80),
          const SizedBox(height: 32),

          // Skeleton de metas mensais
          SkeletonText(
            width: 120,
            height: 20,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          SkeletonCard(
            height: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  width: 100,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                SkeletonText(
                  width: double.infinity,
                  height: 8,
                  borderRadius: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonText(width: 80, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar dados',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.primary,
                foregroundColor: ThemeHelpers.onPrimaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Retorna saudação dinâmica baseada na hora
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 12) {
      return 'Bom dia';
    } else if (hour >= 12 && hour < 18) {
      return 'Boa tarde';
    } else {
      return 'Boa noite';
    }
  }

  /// Formata data completa em português
  String _formatFullDate() {
    return DateFormat(
      "EEEE, d 'de' MMMM 'de' yyyy",
      'pt_BR',
    ).format(DateTime.now());
  }

  Widget _buildGreeting(BuildContext context, ThemeData theme) {
    final userName = _dashboardData?.user.name ?? 'Usuário';
    final firstName = userName.trim().isEmpty ? 'Usuário' : userName.trim().split(' ').first;
    final performance = _dashboardData?.performance;
    final stats = _dashboardData?.stats;
    final accent = _dashboardAccentColor(context);

    Widget greetingIcon() {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [accent, const Color(0xFF7C3AED)],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.dashboard_customize_outlined, color: Colors.white, size: 22),
      );
    }

    Widget pillRow() {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildFilterPill(context, Icons.date_range_outlined, _activePeriodLabel()),
          _buildFilterPill(context, Icons.compare_arrows_outlined, _activeComparisonLabel()),
          _buildFilterPill(context, Icons.insights_outlined, _activeMetricLabel()),
        ],
      );
    }

    final mainTitles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PAINEL GERAL',
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_getGreeting()}, $firstName',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.05,
          ),
        ),
      ],
    );

    final dateLine = Text(
      'Visão executiva · ${_formatFullDate()}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
        height: 1.3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
              final w = constraints.maxWidth;
              final spread = w >= 480;
              final actionsTop = w >= 640;
              // Linha extra: filtros | insight lado a lado (mais “app”, menos torre).
              final pillsBesideInsight = w >= 520;

              if (!spread) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        greetingIcon(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              mainTitles,
                              const SizedBox(height: 6),
                              dateLine,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    pillRow(),
                    const SizedBox(height: 10),
                    _buildInsightPanel(context, theme, performance, stats),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildHeaderActions(context, theme),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      greetingIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 52,
                              child: mainTitles,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 48,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: dateLine,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (actionsTop) ...[
                        const SizedBox(width: 12),
                        _buildHeaderActions(context, theme),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pillsBesideInsight)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 40,
                          child: pillRow(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 60,
                          child: _buildInsightPanel(context, theme, performance, stats),
                        ),
                      ],
                    )
                  else ...[
                    pillRow(),
                    const SizedBox(height: 10),
                    _buildInsightPanel(context, theme, performance, stats),
                  ],
                  if (!actionsTop) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildHeaderActions(context, theme),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }

  Widget _buildHeaderActions(BuildContext context, ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        _buildHeaderActionButton(
          context: context,
          icon: Icons.refresh_rounded,
          label: 'Atualizar',
          onTap: _loadDashboardData,
        ),
        _buildHeaderActionButton(
          context: context,
          icon: Icons.tune_rounded,
          label: 'Filtros',
          isPrimary: true,
          onTap: () => _showFiltersDialog(context),
        ),
      ],
    );
  }

  Widget _buildHeaderActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final accent = _dashboardAccentColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isPrimary ? accent : _glassFillColor(context),
          border: Border.all(color: isPrimary ? accent : _glassBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isPrimary ? Colors.white : accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isPrimary ? Colors.white : ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightPanel(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance? performance,
    DashboardStats? stats,
  ) {
    final growth = performance?.growthPercentage ?? 0;
    final isPositive = growth >= 0;
    final accent = isPositive ? AppColors.status.success : AppColors.status.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.14),
            ),
            child: Icon(
              isPositive ? Icons.trending_up_rounded : Icons.warning_amber_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSIGHT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  performance == null
                      ? 'Acompanhe a sua performance assim que os dados forem carregados.'
                      : '${isPositive ? 'Crescimento' : 'Queda'} de ${growth.abs().toStringAsFixed(1)}% vs. período anterior · ${_formatCurrency(performance.thisMonth)} no mês.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(BuildContext context, IconData icon, String label) {
    final accent = _dashboardAccentColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection(BuildContext context, ThemeData theme) {
    final achievements = _dashboardData?.gamification.achievements ?? [];
    if (achievements.isEmpty) return const SizedBox.shrink();

    return _buildDashboardPanel(
      context: context,
      title: 'Conquistas',
      eyebrow: 'GAMIFICAÇÃO',
      icon: Icons.workspace_premium_outlined,
      elevatedSurface: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final itemWidth = width >= 900 ? (width - 60) / 4 : width >= 620 ? (width - 40) / 3 : (width - 12) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: achievements.take(6).map((achievement) {
              return SizedBox(
                width: itemWidth,
                child: LayoutBuilder(
                  builder: (context, cell) {
                    final rowLayout = cell.maxWidth >= 168;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _inlineTileDecoration(context, radius: 16),
                      child: rowLayout
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(achievement.icon, style: const TextStyle(fontSize: 26)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    achievement.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(achievement.icon, style: const TextStyle(fontSize: 26)),
                                const SizedBox(height: 8),
                                Text(
                                  achievement.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: ThemeHelpers.textColor(context),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                    );
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildStatsCards(BuildContext context, ThemeData theme) {
    final stats = _dashboardData?.stats ?? DashboardStats.empty;

    final cards = [
      _buildSummaryCard(context: context, theme: theme, title: 'Imóveis', value: _formatNumber(stats.myProperties), icon: Icons.home_work_outlined, color: const Color(0xFF6366F1)),
      _buildSummaryCard(context: context, theme: theme, title: 'Clientes', value: _formatNumber(stats.myClients), icon: Icons.groups_2_outlined, color: const Color(0xFF10B981)),
      _buildSummaryCard(context: context, theme: theme, title: 'Vistorias', value: _formatNumber(stats.myInspections), icon: Icons.fact_check_outlined, color: const Color(0xFFF59E0B)),
      _buildSummaryCard(context: context, theme: theme, title: 'Comissões', value: _formatCurrency(stats.myCommissions), icon: Icons.payments_outlined, color: const Color(0xFFEC4899)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 860
            ? 4
            : width > _kStatsHScrollMaxW
                ? 2
                : (width >= 340 ? 2 : 1);
        final spacing = width >= 620 ? 10.0 : 8.0;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) => SizedBox(width: itemWidth, child: card)).toList(),
        );
      },
    );
  }

  Widget _buildActivitiesSection(BuildContext context, ThemeData theme) {
    final stats = _dashboardData?.stats ?? DashboardStats.empty;
    final activityStats = _dashboardData?.activityStats;

    return _buildDashboardPanel(
      context: context,
      title: 'Operação ativa',
      eyebrow: 'RITMO DO DIA',
      icon: Icons.bolt_outlined,
      child: LayoutBuilder(
        builder: (context, outer) {
          Widget cardsArea() {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 560;
                final spacing = isWide ? 10.0 : 8.0;
                final itemWidth = isWide ? (constraints.maxWidth - spacing * 2) / 3 : constraints.maxWidth;
                final cards = [
                  _buildActivityCard(context: context, theme: theme, title: 'Tarefas', value: _formatNumber(stats.myTasks), subtitle: 'Em andamento', icon: Icons.assignment_turned_in_outlined, color: const Color(0xFF6366F1)),
                  _buildActivityCard(context: context, theme: theme, title: 'Agendamentos', value: _formatNumber(activityStats?.appointmentsThisMonth ?? 0), subtitle: 'Este mês', icon: Icons.event_available_outlined, color: const Color(0xFFF59E0B)),
                  _buildActivityCard(context: context, theme: theme, title: 'Matches', value: _formatNumber(stats.myMatches), subtitle: 'Pendentes', icon: Icons.favorite_border_rounded, color: const Color(0xFF10B981)),
                ];
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: cards.map((card) => SizedBox(width: itemWidth, child: card)).toList(),
                );
              },
            );
          }

          final strip = activityStats != null
              ? _buildProgressStrip(
                  context: context,
                  label: 'Taxa de conclusão',
                  valueLabel: '${activityStats.completionRate.toStringAsFixed(1)}%',
                  value: (activityStats.completionRate / 100).clamp(0.0, 1.0).toDouble(),
                  color: _dashboardAccentColor(context),
                )
              : null;

          final besideStrip = outer.maxWidth >= 520 && strip != null;

          if (besideStrip) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 58,
                  child: cardsArea(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 42,
                  child: strip,
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cardsArea(),
              if (strip != null) ...[
                const SizedBox(height: 10),
                strip,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivityCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final spread = c.maxWidth >= 400;
        final valueText = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        );
        final titleText = Text(
          title.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        final subtitleW = subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : null;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: _inlineTileDecoration(context, radius: 18, accent: color),
          child: spread
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIconBadge(context, icon, color, size: 38, iconSize: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          valueText,
                          const SizedBox(height: 4),
                          titleText,
                          if (subtitleW != null) subtitleW,
                        ],
                      ),
                    ),
                    Icon(Icons.more_horiz_rounded, color: ThemeHelpers.textSecondaryColor(context), size: 18),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildIconBadge(context, icon, color, size: 38, iconSize: 18),
                        Icon(Icons.more_horiz_rounded, color: ThemeHelpers.textSecondaryColor(context), size: 18),
                      ],
                    ),
                    const SizedBox(height: 10),
                    valueText,
                    const SizedBox(height: 4),
                    titleText,
                    if (subtitleW != null) subtitleW,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPerformanceCard(BuildContext context, ThemeData theme) {
    final performance = _dashboardData?.performance;
    final gamification =
        _dashboardData?.gamification ?? DashboardGamification.empty();
    if (performance == null) return const SizedBox.shrink();

    final growthPositive = performance.growthPercentage >= 0;
    final growthColor = growthPositive ? AppColors.status.success : AppColors.status.error;

    return _buildDashboardPanel(
      context: context,
      title: 'Performance mensal',
      eyebrow: 'META · PROJEÇÃO · RANKING',
      icon: Icons.query_stats_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: growthColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: growthColor.withOpacity(0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(growthPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: growthColor, size: 18),
            const SizedBox(width: 6),
            Text(
              '${performance.growthPercentage.toStringAsFixed(1)}%',
              style: theme.textTheme.labelLarge?.copyWith(color: growthColor, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final topSpread = c.maxWidth >= 520;
          final miniCards = [
            _buildMiniInfoCard(context, 'Ranking', '#${performance.ranking} de ${performance.totalUsers}', Icons.emoji_events_outlined, const Color(0xFFF59E0B)),
            _buildMiniInfoCard(context, 'Nível', 'Nível ${gamification.level}', Icons.auto_awesome_outlined, const Color(0xFF8B5CF6)),
            _buildMiniInfoCard(context, 'Pontos', '${gamification.currentPoints}', Icons.stars_outlined, const Color(0xFF06B6D4)),
          ];

          final valueBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCurrency(performance.thisMonth),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Resultado acumulado no período selecionado, comparado ao ciclo anterior.',
                style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context)),
              ),
            ],
          );

          Widget miniLayout() {
            return LayoutBuilder(
              builder: (context, c2) {
                final row3 = c2.maxWidth >= 400;
                if (!row3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < miniCards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        miniCards[i],
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: miniCards[0]),
                    const SizedBox(width: 10),
                    Expanded(child: miniCards[1]),
                    const SizedBox(width: 10),
                    Expanded(child: miniCards[2]),
                  ],
                );
              },
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topSpread)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 50,
                      child: valueBlock,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 50,
                      child: miniLayout(),
                    ),
                  ],
                )
              else ...[
                valueBlock,
                const SizedBox(height: 12),
                miniLayout(),
              ],
              const SizedBox(height: 14),
              Text(
                'Breakdown de pontos'.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              _buildPointsBreakdown(
                gamification.pointsBreakdown,
                theme,
                layoutWidth: c.maxWidth,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPointsBreakdown(
    DashboardPointsBreakdown breakdown,
    ThemeData theme, {
    double? layoutWidth,
  }) {
    final total = breakdown.sales + breakdown.rentals + breakdown.clients + breakdown.appointments + breakdown.tasks + breakdown.other;
    if (total == 0) {
      return Text('Nenhum ponto registrado', style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context)));
    }
    final twoCols = layoutWidth != null && layoutWidth >= 520;
    final bars = <Widget>[
      _buildBreakdownBar(label: 'Vendas', value: breakdown.sales, total: total, color: AppColors.status.success, theme: theme),
      _buildBreakdownBar(label: 'Aluguéis', value: breakdown.rentals, total: total, color: Colors.pinkAccent, theme: theme),
      _buildBreakdownBar(label: 'Clientes', value: breakdown.clients, total: total, color: _dashboardAccentColor(context), theme: theme),
      _buildBreakdownBar(label: 'Agendamentos', value: breakdown.appointments, total: total, color: Colors.orangeAccent, theme: theme),
      _buildBreakdownBar(label: 'Tarefas', value: breakdown.tasks, total: total, color: Colors.deepPurpleAccent, theme: theme),
      _buildBreakdownBar(label: 'Outros', value: breakdown.other, total: total, color: Colors.blueGrey, theme: theme),
    ];

    if (twoCols) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                bars[0],
                const SizedBox(height: 6),
                bars[1],
                const SizedBox(height: 6),
                bars[2],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                bars[3],
                const SizedBox(height: 6),
                bars[4],
                const SizedBox(height: 6),
                bars[5],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        bars[0],
        const SizedBox(height: 6),
        bars[1],
        const SizedBox(height: 6),
        bars[2],
        const SizedBox(height: 6),
        bars[3],
        const SizedBox(height: 6),
        bars[4],
        const SizedBox(height: 6),
        bars[5],
      ],
    );
  }

  Widget _buildBreakdownBar({
    required String label,
    required int value,
    required int total,
    required Color color,
    required ThemeData theme,
  }) {
    final percentage = total > 0 ? (value / total).clamp(0.0, 1.0).toDouble() : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 9, color: color.withOpacity(0.12)),
                FractionallySizedBox(
                  widthFactor: percentage,
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withOpacity(0.75), color]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text('$value', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _buildUpcomingAppointments(BuildContext context, ThemeData theme) {
    final appointments = _dashboardData?.upcomingAppointments ?? [];
    return _buildDashboardPanel(
      context: context,
      title: 'Próximos compromissos',
      eyebrow: 'AGENDA',
      icon: Icons.calendar_month_outlined,
      elevatedSurface: false,
      trailing: TextButton.icon(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.calendar),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('Ver todos'),
      ),
      child: appointments.isNotEmpty
          ? Column(children: appointments.take(5).map((appointment) => _buildAppointmentCard(context: context, theme: theme, appointment: appointment)).toList())
          : _buildEmptyState(
              icon: Icons.calendar_today_outlined,
              title: 'Nenhum agendamento',
              message: 'Você não tem compromissos agendados no momento. Que tal agendar uma visita?',
              actionLabel: 'Ir para Agenda',
              onAction: () => Navigator.of(context).pushNamed(AppRoutes.calendar),
              isCard: false,
            ),
    );
  }

  Widget _buildAppointmentCard({
    required BuildContext context,
    required ThemeData theme,
    required DashboardAppointment appointment,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.calendarDetails(appointment.id)),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        decoration: BoxDecoration(
          border: Border(
            left: const BorderSide(color: Color(0xFF6366F1), width: 3),
            bottom: BorderSide(color: _glassBorderColor(context)),
          ),
        ),
        child: Row(
          children: [
            _buildIconBadge(context, Icons.calendar_today_rounded, const Color(0xFF6366F1), size: 36, iconSize: 18),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final lineSpread = c.maxWidth >= 320;
                  if (!lineSpread) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appointment.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(appointment.client, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 14, color: ThemeHelpers.textSecondaryColor(context)),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${appointment.date} às ${appointment.time}', style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              appointment.title,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${appointment.date}\n${appointment.time}',
                            style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w800),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(appointment.client, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  );
                },
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ThemeHelpers.textSecondaryColor(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivities(BuildContext context, ThemeData theme) {
    final activities = _dashboardData?.recentActivities ?? [];
    return _buildDashboardPanel(
      context: context,
      title: 'Atividades recentes',
      eyebrow: 'TIMELINE',
      icon: Icons.history_rounded,
      elevatedSurface: false,
      child: activities.isNotEmpty
          ? Column(children: activities.take(5).map((activity) => _buildActivityItem(context: context, theme: theme, activity: activity)).toList())
          : _buildEmptyState(
              icon: Icons.history_outlined,
              title: 'Nenhuma atividade recente',
              message: 'Suas atividades aparecerão aqui conforme você usar o sistema.',
              actionLabel: null,
              onAction: null,
              isCard: false,
            ),
    );
  }

  Widget _buildActivityItem({
    required BuildContext context,
    required ThemeData theme,
    required DashboardActivity activity,
  }) {
    final accent = _dashboardAccentColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _glassBorderColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10)])),
              Container(width: 2, height: 44, color: accent.withOpacity(0.18)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 2, top: 2, bottom: 10, right: 2),
              child: LayoutBuilder(
                builder: (context, c) {
                  final spread = c.maxWidth >= 340;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (spread) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                activity.title,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              activity.time,
                              style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w800, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(activity.description, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context))),
                      ]
                      else ...[
                        Text(activity.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context))),
                        const SizedBox(height: 4),
                        Text(activity.description, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context))),
                        const SizedBox(height: 6),
                        Text(activity.time, style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyGoalsSection(BuildContext context, ThemeData theme) {
    final goals = _dashboardData?.monthlyGoals;
    final hasGoals = goals != null && (goals.sales != null || goals.commissions != null);
    return _buildDashboardPanel(
      context: context,
      title: 'Metas mensais',
      eyebrow: 'OBJETIVOS',
      icon: Icons.track_changes_rounded,
      elevatedSurface: false,
      child: hasGoals
          ? _buildGoalsContent(context, theme, goals)
          : _buildEmptyState(
              icon: Icons.track_changes_outlined,
              title: 'Nenhuma meta definida',
              message: 'Configure suas metas mensais para acompanhar seu progresso e alcançar seus objetivos!',
              actionLabel: null,
              onAction: null,
              isCard: false,
            ),
    );
  }

  Widget _buildGoalsContent(BuildContext context, ThemeData theme, DashboardMonthlyGoals goals) {
    return LayoutBuilder(
      builder: (context, c) {
        final sideBySide = c.maxWidth >= 480 && goals.sales != null && goals.commissions != null;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildGoalProgress(
                  context: context,
                  theme: theme,
                  label: 'Vendas',
                  current: goals.sales!.current.toInt(),
                  target: goals.sales!.target.toInt(),
                  percentage: goals.sales!.percentage,
                  icon: Icons.home_work_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildGoalProgress(
                  context: context,
                  theme: theme,
                  label: 'Comissões',
                  current: goals.commissions!.current.toInt(),
                  target: goals.commissions!.target.toInt(),
                  percentage: goals.commissions!.percentage,
                  icon: Icons.payments_outlined,
                  isCurrency: true,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (goals.sales != null)
              _buildGoalProgress(context: context, theme: theme, label: 'Vendas', current: goals.sales!.current.toInt(), target: goals.sales!.target.toInt(), percentage: goals.sales!.percentage, icon: Icons.home_work_outlined),
            if (goals.sales != null && goals.commissions != null) const SizedBox(height: 12),
            if (goals.commissions != null)
              _buildGoalProgress(context: context, theme: theme, label: 'Comissões', current: goals.commissions!.current.toInt(), target: goals.commissions!.target.toInt(), percentage: goals.commissions!.percentage, icon: Icons.payments_outlined, isCurrency: true),
          ],
        );
      },
    );
  }

  Widget _buildGoalProgress({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required int current,
    required int target,
    required double percentage,
    required IconData icon,
    bool isCurrency = false,
  }) {
    final color = percentage >= 100 ? AppColors.status.success : _dashboardAccentColor(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _inlineTileDecoration(context, radius: 16, accent: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildIconBadge(context, icon, color, size: 38, iconSize: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)))),
              Text('${percentage.toStringAsFixed(1)}%', style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          _buildProgressStrip(
            context: context,
            label: isCurrency ? '${_formatCurrency(current.toDouble())} / ${_formatCurrency(target.toDouble())}' : '${_formatNumber(current)} / ${_formatNumber(target)}',
            valueLabel: '${percentage.toStringAsFixed(1)}% concluído',
            value: (percentage / 100).clamp(0.0, 1.0).toDouble(),
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildConversionMetrics(BuildContext context, ThemeData theme) {
    final metrics = _dashboardData?.conversionMetrics;
    if (metrics == null) return const SizedBox.shrink();
    return _buildDashboardPanel(
      context: context,
      title: 'Métricas de conversão',
      eyebrow: 'EFICIÊNCIA',
      icon: Icons.insights_outlined,
      elevatedSurface: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 340;
          final cards = [
            _buildMetricItem(theme: theme, label: 'Taxa Visitas/Vendas', value: '${metrics.visitsToSales.toStringAsFixed(1)}%', icon: Icons.show_chart_rounded),
            _buildMetricItem(theme: theme, label: 'Matches Aceitos', value: _formatNumber(metrics.matchesAccepted), icon: Icons.favorite_rounded),
          ];
          if (!isWide) return Column(children: [cards[0], const SizedBox(height: 10), cards[1]]);
          return Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]);
        },
      ),
    );
  }

  Widget _buildMetricItem({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
  }) {
    final accent = _dashboardAccentColor(context);
    return LayoutBuilder(
      builder: (context, c) {
        final spread = c.maxWidth >= 280;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: _inlineTileDecoration(context, radius: 16, accent: accent),
          child: spread
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIconBadge(context, icon, accent, size: 38, iconSize: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context))),
                          const SizedBox(height: 4),
                          Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIconBadge(context, icon, accent, size: 38, iconSize: 18),
                    const SizedBox(height: 12),
                    Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context))),
                    const SizedBox(height: 4),
                    Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                  ],
                ),
        );
      },
    );
  }

  /// Formata valores monetários com máscara brasileira
  String _formatCurrency(double value) {
    if (value == 0) return 'R\$ 0,00';

    // Para valores muito grandes, usar formato compacto
    if (value >= 1000000000) {
      final billions = value / 1000000000;
      return 'R\$ ${billions.toStringAsFixed(billions >= 10 ? 1 : 2)}B';
    } else if (value >= 1000000) {
      final millions = value / 1000000;
      return 'R\$ ${millions.toStringAsFixed(millions >= 10 ? 1 : 2)}M';
    } else if (value >= 1000) {
      final thousands = value / 1000;
      return 'R\$ ${thousands.toStringAsFixed(thousands >= 10 ? 1 : 2)}k';
    }

    // Para valores menores, usar formatação completa com separadores
    return _currencyFormatter.format(value);
  }

  /// Formata números grandes com separadores
  String _formatNumber(int value) {
    if (value == 0) return '0';
    return _numberFormatter.format(value);
  }

  Widget _buildDashboardPanel({
    required BuildContext context,
    required String title,
    required String eyebrow,
    required IconData icon,
    required Widget child,
    Widget? trailing,
    bool elevatedSurface = true,
  }) {
    final accent = _dashboardAccentColor(context);
    final theme = Theme.of(context);

    final headerIcon = elevatedSurface
        ? _buildIconBadge(context, icon, accent, size: 40, iconSize: 20)
        : Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: accent.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.10),
            ),
            child: Icon(icon, color: accent, size: 22),
          );

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headerIcon,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (elevatedSurface) const SizedBox(height: 12) else const SizedBox(height: 10),
        if (!elevatedSurface) ...[
          Container(
            height: 3,
            width: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: [accent, accent.withOpacity(0.15)],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        child,
      ],
    );

    if (!elevatedSurface) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: body,
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(context),
      child: body,
    );
  }

  /// Widget para exibir estado vazio com mensagem amigável
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool isCard = true,
  }) {
    final theme = Theme.of(context);
    final accent = _dashboardAccentColor(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIconBadge(context, icon, accent, size: 58, iconSize: 28),
        const SizedBox(height: 14),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: ThemeHelpers.textColor(context)), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: ThemeHelpers.textSecondaryColor(context), height: 1.35), textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          _buildHeaderActionButton(context: context, icon: Icons.arrow_forward_rounded, label: actionLabel, isPrimary: true, onTap: onAction),
        ],
      ],
    );

    if (isCard) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _inlineTileDecoration(context, radius: 24),
        child: content,
      );
    }

    return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: content);
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    // Altura fixa: filhos de `Wrap` têm altura máxima ilimitada — `Spacer`/`Expanded`
    // no eixo vertical quebram o layout e podem deixar o dashboard em branco.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 122,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(isDark ? 0.16 : 0.11),
            color.withOpacity(isDark ? 0.05 : 0.04),
          ],
        ),
        border: Border.all(color: _glassBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIconBadge(context, icon, color, size: 36, iconSize: 17),
              Container(
                width: 38,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(colors: [color.withOpacity(0.16), color.withOpacity(0.72)]),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfoCard(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _inlineTileDecoration(context, radius: 16, accent: color),
      child: Row(
        children: [
          _buildIconBadge(context, icon, color, size: 36, iconSize: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.titleSmall?.copyWith(color: ThemeHelpers.textColor(context), fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBadge(BuildContext context, IconData icon, Color color, {double size = 44, double iconSize = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.33),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.95), color.withOpacity(0.62)],
        ),
        boxShadow: [BoxShadow(color: color.withOpacity(0.24), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  Widget _buildProgressStrip({
    required BuildContext context,
    required String label,
    required String valueLabel,
    required double value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: ThemeHelpers.textSecondaryColor(context), fontWeight: FontWeight.w800))),
            Text(valueLabel, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 9, color: color.withOpacity(0.12)),
              FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.75), color])),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _dashboardAccentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF4D67) : AppColors.primary.primary;
  }

  Color _glassFillColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.045) : Colors.white.withOpacity(0.72);
  }

  Color _glassBorderColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.055);
  }

  /// Orbes desfocados por trás do conteúdo — leitura em camadas sem mais um “card” no topo.
  List<Widget> _dashboardAmbientHighlights(BuildContext context) {
    final accent = _dashboardAccentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cool = isDark ? const Color(0xFF4F46E5) : const Color(0xFF818CF8);
    return [
      Positioned(
        top: -72,
        right: -48,
        child: IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withOpacity(isDark ? 0.26 : 0.16),
                  accent.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 280,
        left: -110,
        child: IgnorePointer(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withOpacity(isDark ? 0.18 : 0.10),
                  cool.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Superfície leve para itens em secções “no fundo” (sem painel elevado).
  BoxDecoration _inlineTileDecoration(BuildContext context, {double radius = 16, Color? accent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = accent ?? _dashboardAccentColor(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: isDark ? Colors.white.withOpacity(0.042) : Colors.white.withOpacity(0.5),
      border: Border.all(color: a.withOpacity(isDark ? 0.12 : 0.065)),
    );
  }

  BoxDecoration _panelDecoration(BuildContext context, {Color? accent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAccent = accent ?? _dashboardAccentColor(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF16151E), const Color(0xFF0E0E14)]
            : [Colors.white, const Color(0xFFFFFCFC)],
      ),
      border: Border.all(color: effectiveAccent.withOpacity(isDark ? 0.16 : 0.09)),
      boxShadow: [
        BoxShadow(
          color: effectiveAccent.withOpacity(isDark ? 0.14 : 0.07),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.04),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  String _activePeriodLabel() {
    switch (_filters.dateRange) {
      case '7d':
        return 'Últimos 7 dias';
      case '30d':
        return 'Últimos 30 dias';
      case '90d':
        return 'Últimos 90 dias';
      case 'custom':
        return 'Período personalizado';
      default:
        return 'Período atual';
    }
  }

  String _activeComparisonLabel() {
    switch (_filters.compareWith) {
      case 'previous_period':
        return 'Comparando período';
      case 'previous_year':
        return 'Comparando ano';
      case 'none':
        return 'Sem comparação';
      default:
        return 'Comparação ativa';
    }
  }

  String _activeMetricLabel() {
    switch (_filters.metric) {
      case 'sales':
        return 'Vendas';
      case 'commissions':
        return 'Comissões';
      case 'properties':
        return 'Imóveis';
      case 'clients':
        return 'Clientes';
      default:
        return 'Todas as métricas';
    }
  }
}
