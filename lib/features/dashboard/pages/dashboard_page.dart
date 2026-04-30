import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
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

  /// Shimmer espelha o mesmo “esqueleto” do dashboard carregado: padding, Stack,
  /// espaçamentos, breakpoints de coluna e ordem das secções.
  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final viewportW = constraints.maxWidth;

        Widget content(Column column) =>
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kPagePadH,
                _kPagePadTop,
                _kPagePadH,
                _kPagePadBottom,
              ),
              child: column,
            );

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: h),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ..._dashboardAmbientHighlights(context),
                content(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dashboardSkeletonHero(context, viewportW),
                      SizedBox(height: _kSectionGap + 2),
                      _dashboardSkeletonSummaryStrip(context, viewportW),
                      SizedBox(height: _kSectionGap),
                      _dashboardSkeletonPerfAndActivities(context, viewportW),
                      SizedBox(height: _kSectionGap),
                      _dashboardSkeletonGoalsAndConversion(context, viewportW),
                      SizedBox(height: _kSectionGap),
                      _dashboardSkeletonAchievements(context, viewportW),
                      SizedBox(height: _kSectionGap),
                      _dashboardSkeletonTimelineAndAgenda(context, viewportW),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dashboardSkeletonHero(BuildContext context, double w) {
    final spread = w >= 480;
    final actionsTop = w >= 640;
    final pillsBesideInsight = w >= 520;

    final iconPlate = SkeletonBox(
      width: 40,
      height: 40,
      borderRadius: 14,
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonText(width: min(118, w * 0.34), height: 11, borderRadius: 4),
        const SizedBox(height: 8),
        SkeletonText(width: min(290, w * 0.72), height: 22, borderRadius: 6),
        const SizedBox(height: 8),
        SkeletonText(width: min(320, w * 0.88), height: 13, borderRadius: 4),
      ],
    );

    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SkeletonBox(width: min(124, w * 0.36), height: 32, borderRadius: 999),
        SkeletonBox(width: min(142, w * 0.4), height: 32, borderRadius: 999),
        SkeletonBox(width: min(118, w * 0.34), height: 32, borderRadius: 999),
      ],
    );

    final insight = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 44, height: 44, borderRadius: 999),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 64, height: 10),
              const SizedBox(height: 6),
              SkeletonText(width: double.infinity, height: 13),
              const SizedBox(height: 6),
              SkeletonText(width: min(260, w * 0.62), height: 13),
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        SkeletonBox(width: 118, height: 42, borderRadius: 16),
        SkeletonBox(width: 104, height: 42, borderRadius: 16),
      ],
    );

    Widget narrowLayout() =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconPlate,
                const SizedBox(width: 12),
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: 12),
            pills,
            const SizedBox(height: 10),
            insight,
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: actions,
            ),
          ],
        );

    Widget wideLayout() =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconPlate,
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 52, child: titleBlock),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 48,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SkeletonText(
                                width: min(212, w * 0.38),
                                height: 12,
                              ),
                              const SizedBox(height: 6),
                              SkeletonText(
                                width: min(188, w * 0.34),
                                height: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionsTop) ...[
                  const SizedBox(width: 12),
                  actions,
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (pillsBesideInsight)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 40, child: pills),
                  const SizedBox(width: 12),
                  Expanded(flex: 60, child: insight),
                ],
              )
            else ...[
              pills,
              const SizedBox(height: 10),
              insight,
            ],
            if (!actionsTop) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: actions,
              ),
            ],
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: spread ? wideLayout() : narrowLayout(),
    );
  }

  Widget _dashboardSkeletonSummaryStrip(BuildContext context, double width) {
    final columns = width >= 860
        ? 4
        : width > _kStatsHScrollMaxW
            ? 2
            : (width >= 340 ? 2 : 1);
    final spacing = width >= 620 ? 10.0 : 8.0;
    final inner = width - spacing * (columns - 1);
    final itemWidth = inner / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: List.generate(
        4,
        (_) =>
            SizedBox(width: itemWidth, child: _dashboardSkeletonSummaryTile(context)),
      ),
    );
  }

  Widget _dashboardSkeletonSummaryTile(BuildContext context) {
    return Container(
      height: 122,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
        color: ThemeHelpers.cardBackgroundColor(context).withValues(alpha: 0.42),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 36, height: 36, borderRadius: 12),
              SkeletonBox(width: 38, height: 6, borderRadius: 999),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 92, height: 24, borderRadius: 6),
              const SizedBox(height: 6),
              SkeletonText(width: 76, height: 12, borderRadius: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonPerfAndActivities(BuildContext context, double w) {
    final perf = _dashboardSkeletonPerformancePanel(context);
    if (w < _kPerfActivityRowMinW) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          perf,
          SizedBox(height: _kSectionGap),
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonOperationsPanel(context, c.maxWidth),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 12, child: perf),
        SizedBox(width: _kSectionGap),
        Expanded(
          flex: 10,
          child: LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonOperationsPanel(context, c.maxWidth),
          ),
        ),
      ],
    );
  }

  Widget _dashboardSkeletonPerformancePanel(BuildContext context) {
    Widget miniRail() =>
        Column(
          children: [
            SkeletonText(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            SkeletonText(width: 48, height: 22),
          ],
        );

    return SkeletonCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 44, height: 44, borderRadius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 132, height: 10),
                    const SizedBox(height: 4),
                    SkeletonText(width: 178, height: 16),
                  ],
                ),
              ),
              SkeletonBox(width: 76, height: 34, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 12),
          SkeletonBox(
            width: double.infinity,
            height: 152,
            borderRadius: 22,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: miniRail()),
              const SizedBox(width: 8),
              Expanded(child: miniRail()),
              const SizedBox(width: 8),
              Expanded(child: miniRail()),
            ],
          ),
          const SizedBox(height: 16),
          SkeletonText(width: 168, height: 11),
          const SizedBox(height: 6),
          SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 38, borderRadius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 38, borderRadius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 38, borderRadius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 38, borderRadius: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonFlatHeader(
    BuildContext context,
    double maxW, {
    required double titleW,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 44, height: 44, borderRadius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 96, height: 10),
              const SizedBox(height: 4),
              SkeletonText(width: min(titleW, maxW * 0.72), height: 16),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _dashboardSkeletonOperationsPanel(BuildContext context, double innerW) {
    final pairRow = innerW >= 340;
    final trafficH = pairRow ? 132.0 : 116.0;
    final completionH = pairRow ? 132.0 : 108.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(context, innerW, titleW: 168),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          SkeletonBox(
            width: double.infinity,
            height: 88,
            borderRadius: 18,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 58, borderRadius: 14)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 58, borderRadius: 14)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 58, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 8),
          if (pairRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SkeletonBox(
                    height: trafficH,
                    borderRadius: 14,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SkeletonBox(
                    height: completionH,
                    borderRadius: 14,
                    width: double.infinity,
                  ),
                ),
              ],
            )
          else ...[
            SkeletonBox(height: trafficH, borderRadius: 14, width: double.infinity),
            const SizedBox(height: 8),
            SkeletonBox(
              height: completionH,
              borderRadius: 14,
              width: double.infinity,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dashboardSkeletonGoalsAndConversion(BuildContext context, double w) {
    if (w < _kTwoColMinW) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonGoalsPanel(context, c.maxWidth),
          ),
          SizedBox(height: _kSectionGap),
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonConversionPanel(context, c.maxWidth),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonGoalsPanel(context, c.maxWidth),
          ),
        ),
        SizedBox(width: _kSectionGap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonConversionPanel(context, c.maxWidth),
          ),
        ),
      ],
    );
  }

  Widget _dashboardSkeletonGoalTile(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 38, height: 38, borderRadius: 12),
              const SizedBox(width: 8),
              Expanded(child: SkeletonText(width: double.infinity, height: 14)),
              SkeletonText(width: 44, height: 14),
            ],
          ),
          const SizedBox(height: 10),
          SkeletonText(width: double.infinity, height: 10),
          const SizedBox(height: 8),
          SkeletonBox(
            width: double.infinity,
            height: 9,
            borderRadius: 999,
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonGoalsPanel(BuildContext context, double innerW) {
    final sideBySide = innerW >= 480;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(context, innerW, titleW: 154),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          if (sideBySide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _dashboardSkeletonGoalTile(context)),
                const SizedBox(width: 10),
                Expanded(child: _dashboardSkeletonGoalTile(context)),
              ],
            )
          else ...[
            _dashboardSkeletonGoalTile(context),
            const SizedBox(height: 12),
            _dashboardSkeletonGoalTile(context),
          ],
        ],
      ),
    );
  }

  Widget _dashboardSkeletonMetricTile(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 38, height: 38, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 72, height: 22),
                const SizedBox(height: 8),
                SkeletonText(width: 124, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonConversionPanel(BuildContext context, double innerW) {
    final wideRow = innerW >= 340;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(context, innerW, titleW: 206),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          if (wideRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _dashboardSkeletonMetricTile(context)),
                const SizedBox(width: 10),
                Expanded(child: _dashboardSkeletonMetricTile(context)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dashboardSkeletonMetricTile(context),
                const SizedBox(height: 10),
                _dashboardSkeletonMetricTile(context),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonAchievements(BuildContext context, double w) {
    final itemW = w >= 900 ? (w - 60) / 4 : w >= 620 ? (w - 40) / 3 : (w - 12) / 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(context, w, titleW: 132),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
              6,
              (_) => SizedBox(
                width: itemW.clamp(120.0, 420.0),
                child: SkeletonBox(height: 66, borderRadius: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonRecent(BuildContext context, double innerW) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(context, innerW, titleW: 184),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          ...List.generate(
            4,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      SkeletonBox(width: 10, height: 10, borderRadius: 999),
                      SkeletonBox(width: 2, height: 42, borderRadius: 2),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SkeletonText(
                                width: double.infinity,
                                height: 14,
                              ),
                            ),
                            SkeletonText(width: 44, height: 11),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SkeletonText(width: double.infinity, height: 12),
                        const SizedBox(height: 4),
                        SkeletonText(
                          width: min(220.0, innerW * 0.55),
                          height: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonAgenda(BuildContext context, double innerW) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(
            context,
            innerW,
            titleW: 206,
            trailing: SkeletonBox(width: 92, height: 32, borderRadius: 10),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 36, height: 36, borderRadius: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: double.infinity, height: 16),
                        const SizedBox(height: 6),
                        SkeletonText(
                          width: min(200.0, innerW * 0.5),
                          height: 12,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SkeletonBox(width: 14, height: 14, borderRadius: 4),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SkeletonText(
                                width: double.infinity,
                                height: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 22, height: 22, borderRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonTimelineAndAgenda(BuildContext context, double w) {
    if (w < _kTwoColMinW) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonRecent(context, c.maxWidth),
          ),
          SizedBox(height: _kSectionGap),
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonAgenda(context, c.maxWidth),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonRecent(context, c.maxWidth),
          ),
        ),
        SizedBox(width: _kSectionGap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonAgenda(context, c.maxWidth),
          ),
        ),
      ],
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
      final isDark = Theme.of(context).brightness == Brightness.dark;
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
              color: isDark ? accent.withOpacity(0.35) : Colors.black.withValues(alpha: 0.14),
              blurRadius: isDark ? 14 : 10,
              offset: Offset(0, isDark ? 8 : 5),
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
          color: isPrimary ? accent : ShellVisualTokens.dashboardGlassFill(context),
          border: Border.all(color: isPrimary ? accent : ShellVisualTokens.dashboardGlassBorder(context)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? accent.withOpacity(0.07) : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? accent.withOpacity(0.14) : borderCol.withValues(alpha: 0.55),
        ),
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
                      decoration: ShellVisualTokens.inlineTileDecoration(
                        context,
                        _dashboardAccentColor(context),
                        radius: 16,
                      ),
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

    final segments = <({
      String title,
      String value,
      IconData icon,
      Color color,
    })>[
      (
        title: 'Tarefas',
        value: _formatNumber(stats.myTasks),
        icon: Icons.assignment_turned_in_outlined,
        color: const Color(0xFF6366F1),
      ),
      (
        title: 'Agenda',
        value: _formatNumber(activityStats?.appointmentsThisMonth ?? 0),
        icon: Icons.event_available_outlined,
        color: const Color(0xFFF59E0B),
      ),
      (
        title: 'Matches',
        value: _formatNumber(stats.myMatches),
        icon: Icons.favorite_border_rounded,
        color: const Color(0xFF10B981),
      ),
    ];

    return _buildDashboardPanel(
      context: context,
      title: 'Operação ativa',
      eyebrow: 'RITMO DO DIA',
      icon: Icons.bolt_outlined,
      elevatedSurface: false,
      child: LayoutBuilder(
        builder: (context, c) {
          final hasStats = activityStats != null;
          final pairRow = hasStats && c.maxWidth >= 340;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOperationsMetricsBand(context, theme, segments),
              const SizedBox(height: 10),
              _buildOperationsContextChips(context, theme, stats, activityStats),
              if (hasStats) ...[
                const SizedBox(height: 8),
                if (pairRow)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildOperationsTrafficLine(
                            context,
                            theme,
                            activityStats,
                            compact: true,
                            fillHeight: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildOperationsCompletionInline(
                            context,
                            theme,
                            activityStats,
                            fillHeight: true,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _buildOperationsTrafficLine(
                    context,
                    theme,
                    activityStats,
                    compact: false,
                  ),
                  const SizedBox(height: 8),
                  _buildOperationsCompletionInline(
                    context,
                    theme,
                    activityStats,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildOperationsContextChips(
    BuildContext context,
    ThemeData theme,
    DashboardStats stats,
    DashboardActivityStats? activityStats,
  ) {
    final chips = <({IconData icon, String label, String value, Color color})>[
      (
        icon: Icons.travel_explore_rounded,
        label: 'Visitas',
        value: activityStats != null
            ? _formatNumber(activityStats.totalVisits)
            : '—',
        color: const Color(0xFF818CF8),
      ),
      (
        icon: Icons.vpn_key_rounded,
        label: 'Chaves',
        value: _formatNumber(stats.myKeys),
        color: const Color(0xFFA78BFA),
      ),
      (
        icon: Icons.sticky_note_2_rounded,
        label: 'Notas',
        value: _formatNumber(stats.myNotes),
        color: const Color(0xFFF472B6),
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _buildOperationsMiniChip(
              context,
              theme,
              icon: chips[i].icon,
              label: chips[i].label,
              value: chips[i].value,
              color: chips[i].color,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOperationsMiniChip(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.22 : 0.14),
            color.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.35 : 0.42)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: isDark ? 0.28 : 0.2),
            ),
            child: Icon(icon, size: 15, color: color.withValues(alpha: 0.98)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsTrafficLine(
    BuildContext context,
    ThemeData theme,
    DashboardActivityStats activityStats, {
    bool compact = false,
    bool fillHeight = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    const indigo = Color(0xFF6366F1);
    const lilac = Color(0xFF818CF8);
    final monthAppt = activityStats.appointmentsThisMonth;
    final periodTag = _activePeriodShortLabel();
    final title = compact ? 'Visitas' : 'Fluxo operacional';
    final sub = '$monthAppt ag · ${_formatNumber(activityStats.totalVisits)}';

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                lilac.withValues(alpha: isDark ? 0.35 : 0.28),
                indigo.withValues(alpha: isDark ? 0.2 : 0.15),
              ],
            ),
          ),
          child: Icon(
            Icons.radar_rounded,
            size: compact ? 18 : 20,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: (compact ? theme.textTheme.labelLarge : theme.textTheme.titleSmall)?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: indigo.withValues(alpha: isDark ? 0.28 : 0.12),
                      border: Border.all(color: lilac.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      periodTag,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: lilac.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatNumber(activityStats.totalVisits),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
            ),
            Text(
              'no período',
              style: theme.textTheme.labelSmall?.copyWith(
                color: lilac.withValues(alpha: 0.85),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      height: fillHeight ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lilac.withValues(alpha: isDark ? 0.42 : 0.38)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            indigo.withValues(alpha: isDark ? 0.2 : 0.11),
            (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: isDark ? 0.55 : 0.92),
            lilac.withValues(alpha: isDark ? 0.08 : 0.06),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: indigo.withValues(alpha: isDark ? 0.12 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -10,
          ),
        ],
      ),
      child: fillHeight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const Spacer(),
              ],
            )
          : content,
    );
  }

  Widget _buildOperationsMetricsBand(
    BuildContext context,
    ThemeData theme,
    List<
        ({
          String title,
          String value,
          IconData icon,
          Color color,
        })> segments,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final bandBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFF6366F1).withValues(alpha: 0.28);

    return LayoutBuilder(
      builder: (context, c) {
        final dense = c.maxWidth < 480;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: bandBorder),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF1E1B4B).withValues(alpha: 0.55),
                      const Color(0xFF0F172A).withValues(alpha: 0.94),
                      const Color(0xFF134E4A).withValues(alpha: 0.35),
                    ]
                  : [
                      const Color(0xFFEEF2FF),
                      const Color(0xFFFDF4FF).withValues(alpha: 0.85),
                      const Color(0xFFECFDF5).withValues(alpha: 0.65),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.14 : 0.07),
                blurRadius: 22,
                offset: const Offset(0, 10),
                spreadRadius: -12,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      color: ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: isDark ? 0.35 : 0.45),
                    ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            segments[i].color.withValues(alpha: isDark ? 0.12 : 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: _buildOperationsMetricSegment(
                        context,
                        theme,
                        title: segments[i].title,
                        value: segments[i].value,
                        icon: segments[i].icon,
                        color: segments[i].color,
                        dense: dense,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOperationsMetricSegment(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool dense,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
        : const EdgeInsets.fromLTRB(14, 16, 14, 16);

    if (dense) {
      return Padding(
        padding: pad,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isDark ? 0.35 : 0.25),
                    color.withValues(alpha: isDark ? 0.12 : 0.08),
                  ],
                ),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Icon(icon, color: Colors.white.withValues(alpha: 0.95), size: 20),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.88),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: pad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color,
                  color.withValues(alpha: isDark ? 0.55 : 0.4),
                  color.withValues(alpha: 0.2),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: isDark ? 0.35 : 0.22),
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: isDark ? 0.45 : 0.3),
                  color.withValues(alpha: isDark ? 0.15 : 0.1),
                ],
              ),
              border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
            ),
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.96), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      height: 1.05,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({String label, Color tone}) _operationsCompletionTone(double pct) {
    if (pct >= 85) {
      return (label: 'Ótimo', tone: const Color(0xFF34D399));
    }
    if (pct >= 65) {
      return (label: 'No alvo', tone: const Color(0xFF22D3EE));
    }
    if (pct >= 40) {
      return (label: 'Atenção', tone: const Color(0xFFFBBF24));
    }
    return (label: 'Priorizar', tone: const Color(0xFFF87171));
  }

  Widget _buildOperationsCompletionInline(
    BuildContext context,
    ThemeData theme,
    DashboardActivityStats activityStats, {
    bool fillHeight = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final rate = (activityStats.completionRate / 100).clamp(0.0, 1.0);
    final pctRounded = activityStats.completionRate.round();
    final pctShort = '$pctRounded%';
    final track = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.07);
    const fillA = Color(0xFF14B8A6);
    const fillB = Color(0xFF6366F1);
    final tone = _operationsCompletionTone(activityStats.completionRate);
    final pending = (100 - activityStats.completionRate).clamp(0.0, 100.0);

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.task_alt_rounded,
          size: 21,
          color: fillA.withValues(alpha: 0.98),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Conclusão',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${pending.toStringAsFixed(0)}% em aberto',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          fit: FlexFit.loose,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pctShort,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone.tone,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: tone.tone.withValues(alpha: isDark ? 0.2 : 0.14),
                    border: Border.all(color: tone.tone.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    tone.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone.tone,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: rate,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      fillA.withValues(alpha: 0.92),
                      fillB.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      height: fillHeight ? double.infinity : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fillA.withValues(alpha: isDark ? 0.42 : 0.35),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fillA.withValues(alpha: isDark ? 0.18 : 0.1),
            fillB.withValues(alpha: isDark ? 0.12 : 0.06),
            (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: isDark ? 0.4 : 0.88),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: fillA.withValues(alpha: isDark ? 0.1 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          header,
          if (fillHeight) const Spacer(),
          const SizedBox(height: 10),
          bar,
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(BuildContext context, ThemeData theme) {
    final performance = _dashboardData?.performance;
    final gamification =
        _dashboardData?.gamification ?? DashboardGamification.empty();
    if (performance == null) return const SizedBox.shrink();

    final growthPositive = performance.growthPercentage >= 0;
    final growthColor =
        growthPositive ? AppColors.status.success : AppColors.status.error;
    final accent = _dashboardAccentColor(context);

    return _buildDashboardPanel(
      context: context,
      title: 'Performance mensal',
      eyebrow: 'META · PROJEÇÃO · RANKING',
      icon: Icons.query_stats_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: growthColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: growthColor.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              growthPositive
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: growthColor,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              '${performance.growthPercentage.toStringAsFixed(1)}%',
              style: theme.textTheme.labelLarge?.copyWith(
                color: growthColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPerformanceFinanceHero(context, theme, performance, accent),
          const SizedBox(height: 14),
          _buildPerformanceKpiRail(context, theme, performance, gamification),
          const SizedBox(height: 16),
          Text(
            'COMPOSIÇÃO DE PONTOS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Distribuição por origem em faixa + resumo em chips (sem rolagem).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildPointsCompositionRibbon(context, theme, gamification.pointsBreakdown),
        ],
      ),
    );
  }

  Widget _buildPerformanceFinanceHero(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance performance,
    Color accent,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final headline = theme.textTheme.headlineLarge?.copyWith(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w900,
      letterSpacing: -1.1,
      height: 1.05,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.2 : 0.11),
            accent.withValues(alpha: isDark ? 0.06 : 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.24 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.055 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 440;
          final textCol = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Volume no período',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(height: 8),
              Text(_formatCurrency(performance.thisMonth), style: headline),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    size: 18,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ciclo anterior · ${_formatCurrency(performance.lastMonth)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
          final compare = _buildPerformanceVolumeComparison(
            context,
            theme,
            performance,
            accent,
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 52, child: textCol),
                const SizedBox(width: 14),
                Expanded(flex: 48, child: compare),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textCol,
              const SizedBox(height: 16),
              compare,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPerformanceVolumeComparison(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance performance,
    Color accent,
  ) {
    final maxVol = max(max(performance.thisMonth, performance.lastMonth), 1.0);
    final fThis = (performance.thisMonth / maxVol).clamp(0.1, 1.0);
    final fLast = (performance.lastMonth / maxVol).clamp(0.1, 1.0);
    const cool = Color(0xFF6366F1);

    Widget barBlock(
      String title,
      double frac,
      Color c,
      double value,
    ) {
      return Expanded(
        child: Column(
          children: [
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: c.withValues(alpha: 0.08),
                      border: Border.all(color: c.withValues(alpha: 0.14)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration: const Duration(milliseconds: 650),
                        curve: Curves.easeOutCubic,
                        builder: (context, anim, child) {
                          return Container(
                            width: double.infinity,
                            height: 88 * anim,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  c.withValues(alpha: 0.55),
                                  c,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.withValues(alpha: c == accent ? 0.14 : 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                  spreadRadius: -1,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _formatCurrency(value),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        barBlock('Atual', fThis, accent, performance.thisMonth),
        const SizedBox(width: 12),
        barBlock('Anterior', fLast, cool, performance.lastMonth),
      ],
    );
  }

  Widget _buildPerformanceKpiRail(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance performance,
    DashboardGamification gamification,
  ) {
    final tiles = <(String, String, IconData, Color)>[
      (
        'Ranking',
        '#${performance.ranking} de ${_formatNumber(performance.totalUsers)}',
        Icons.emoji_events_outlined,
        const Color(0xFFF59E0B),
      ),
      (
        'Nível',
        '${gamification.level}',
        Icons.auto_awesome_outlined,
        const Color(0xFF8B5CF6),
      ),
      (
        'Pontos',
        _formatNumber(gamification.currentPoints),
        Icons.stars_outlined,
        const Color(0xFF06B6D4),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final dense = c.maxWidth < 360;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) SizedBox(width: dense ? 8 : 10),
              Expanded(
                child: _buildPerformanceKpiTile(
                  context,
                  theme,
                  label: tiles[i].$1,
                  value: tiles[i].$2,
                  icon: tiles[i].$3,
                  color: tiles[i].$4,
                  dense: dense,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPerformanceKpiTile(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool dense,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: dense ? 10 : 12,
      ),
      decoration: ShellVisualTokens.inlineTileDecoration(
        context,
        color,
        radius: 18,
      ),
      child: Row(
        children: [
          _buildIconBadge(
            context,
            icon,
            color,
            size: dense ? 34 : 40,
            iconSize: dense ? 16 : 19,
          ),
          SizedBox(width: dense ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.85,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsCompositionRibbon(
    BuildContext context,
    ThemeData theme,
    DashboardPointsBreakdown breakdown,
  ) {
    final total = breakdown.sales +
        breakdown.rentals +
        breakdown.clients +
        breakdown.appointments +
        breakdown.tasks +
        breakdown.other;

    if (total == 0) {
      return Text(
        'Nenhum ponto registrado no período.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      );
    }

    final entries = <({int v, Color c, String l})>[
      (v: breakdown.sales, c: AppColors.status.success, l: 'Vendas'),
      (v: breakdown.rentals, c: Colors.pinkAccent, l: 'Aluguéis'),
      (v: breakdown.clients, c: _dashboardAccentColor(context), l: 'Clientes'),
      (v: breakdown.appointments, c: Colors.orangeAccent, l: 'Agendamentos'),
      (v: breakdown.tasks, c: Colors.deepPurpleAccent, l: 'Tarefas'),
      (v: breakdown.other, c: Colors.blueGrey, l: 'Outros'),
    ];

    final active = entries.where((e) => e.v > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final e in active)
                  Expanded(
                    flex: e.v,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            e.c.withValues(alpha: 0.82),
                            e.c,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in entries)
              _buildPointsSourceChip(
                context,
                theme,
                label: e.l,
                value: e.v,
                total: total,
                color: e.c,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPointsSourceChip(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required int value,
    required int total,
    required Color color,
  }) {
    final pct = total > 0 ? (100.0 * value / total) : 0.0;
    final muted = value == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: muted ? 0.14 : 0.38),
        ),
        color: color.withValues(alpha: muted ? 0.045 : 0.09),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: muted ? 0.4 : 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· ${_formatNumber(value)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
            bottom: BorderSide(color: ShellVisualTokens.dashboardGlassBorder(context)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? accent.withOpacity(0.18)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.52);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ShellVisualTokens.dashboardGlassBorder(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? accent.withOpacity(0.35) : Colors.black.withValues(alpha: 0.12),
                      blurRadius: isDark ? 10 : 5,
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 44, color: lineColor),
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
      decoration: ShellVisualTokens.inlineTileDecoration(context, color, radius: 16),
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
          decoration: ShellVisualTokens.inlineTileDecoration(context, accent, radius: 16),
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
    final isDark = theme.brightness == Brightness.dark;

    final headerIcon = elevatedSurface
        ? _buildIconBadge(context, icon, accent, size: 40, iconSize: 20)
        : Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color:
                  isDark ? accent.withOpacity(0.14) : ThemeHelpers.borderLightColor(context).withValues(alpha: 0.88),
              border: isDark
                  ? null
                  : Border.all(color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42)),
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
                colors: isDark
                    ? [accent, accent.withOpacity(0.15)]
                    : [
                        ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
                        accent.withOpacity(0.7),
                      ],
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
      decoration: ShellVisualTokens.elevatedPanelDecoration(
        context,
        _dashboardAccentColor(context),
      ),
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
        decoration: ShellVisualTokens.inlineTileDecoration(
        context,
        _dashboardAccentColor(context),
        radius: 24,
      ),
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
        border: Border.all(
          color: isDark
              ? ShellVisualTokens.dashboardGlassBorder(context)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -1,
                ),
              ],
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

  Widget _buildIconBadge(BuildContext context, IconData icon, Color color, {double size = 44, double iconSize = 22}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        boxShadow: [
          BoxShadow(
            color: isDark ? color.withOpacity(0.24) : Colors.black.withValues(alpha: 0.12),
            blurRadius: isDark ? 16 : 10,
            offset: Offset(0, isDark ? 8 : 4),
          ),
        ],
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

  /// Orbes desfocados por trás do conteúdo — leitura em camadas sem mais um “card” no topo.
  List<Widget> _dashboardAmbientHighlights(BuildContext context) {
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
                  cool.withOpacity(isDark ? 0.14 : 0.065),
                  cool.withOpacity(0),
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
                  cool.withOpacity(isDark ? 0.18 : 0.065),
                  cool.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
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

  /// Rótulo curto para chips e pills (evita corte em telas estreitas).
  String _activePeriodShortLabel() {
    switch (_filters.dateRange) {
      case '7d':
        return '7 dias';
      case '30d':
        return '30 dias';
      case '90d':
        return '90 dias';
      case 'custom':
        return 'Pers.';
      default:
        return 'Atual';
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
