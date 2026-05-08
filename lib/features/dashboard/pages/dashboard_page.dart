import 'dart:async';
import 'dart:math' show cos, max, min, pi, sin;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/services/dashboard_service.dart';
import '../../../../shared/services/module_access_service.dart';
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
                              _buildUpcomingAppointments(context, theme),
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
                      LayoutBuilder(
                        builder: (context, c) =>
                            _dashboardSkeletonAgenda(context, c.maxWidth),
                      ),
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
        const SizedBox(height: 4),
        SkeletonText(width: min(290, w * 0.72), height: 22, borderRadius: 6),
        const SizedBox(height: 6),
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
                                width: min(280, w * 0.44),
                                height: 12,
                                borderRadius: 4,
                              ),
                              const SizedBox(height: 5),
                              SkeletonText(
                                width: min(220, w * 0.38),
                                height: 12,
                                borderRadius: 4,
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
      height: 128,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
        color: ThemeHelpers.cardBackgroundColor(context).withValues(alpha: 0.42),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(
            width: double.infinity,
            height: 3,
            borderRadius: 3,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 44, height: 44, borderRadius: 14),
                      const Spacer(),
                      SkeletonBox(width: 18, height: 18, borderRadius: 6),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(
                        width: double.infinity,
                        height: 28,
                        borderRadius: 6,
                      ),
                      const SizedBox(height: 6),
                      SkeletonText(width: 92, height: 15, borderRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
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

  /// Espelha `_buildPointsCompositionRibbon` (faixa 14px + grelha de legenda).
  Widget _dashboardSkeletonPointsComposition(
    BuildContext context,
    double maxW,
  ) {
    final track = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: ShellVisualTokens.dashboardGlassBorder(context),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SkeletonBox(
          width: double.infinity,
          height: 14,
          borderRadius: 99,
        ),
      ),
    );

    Widget legendRow() {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            SkeletonBox(width: 10, height: 10, borderRadius: 99),
            const SizedBox(width: 8),
            Expanded(
              child: SkeletonText(height: 12, borderRadius: 4),
            ),
            const SizedBox(width: 6),
            SkeletonText(width: 36, height: 12, borderRadius: 4),
          ],
        ),
      );
    }

    const rowCount = 6;
    final twoCols = maxW >= 360;
    if (!twoCols) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          track,
          const SizedBox(height: 14),
          for (var i = 0; i < rowCount; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            legendRow(),
          ],
        ],
      );
    }

    final rows = List<Widget>.generate(rowCount, (_) => legendRow());
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      (i.isEven ? left : right).add(rows[i]);
    }
    Widget col(List<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              items[i],
            ],
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        track,
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: col(left)),
            const SizedBox(width: 10),
            Expanded(child: col(right)),
          ],
        ),
      ],
    );
  }

  Widget _dashboardSkeletonPerformancePanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
                    SkeletonText(width: 182, height: 10),
                    const SizedBox(height: 4),
                    SkeletonText(width: 196, height: 16),
                  ],
                ),
              ),
              SkeletonBox(width: 102, height: 32, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 12),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 16),
          // Hero financeiro inline
          SkeletonText(width: 148, height: 10),
          const SizedBox(height: 10),
          SkeletonText(width: 220, height: 32, borderRadius: 8),
          const SizedBox(height: 16),
          Row(
            children: [
              SkeletonText(width: 56, height: 11),
              const SizedBox(width: 10),
              Expanded(
                child: SkeletonBox(
                  height: 10,
                  borderRadius: 99,
                ),
              ),
              const SizedBox(width: 10),
              SkeletonText(width: 80, height: 12),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SkeletonText(width: 56, height: 11),
              const SizedBox(width: 10),
              Expanded(
                child: SkeletonBox(
                  height: 10,
                  borderRadius: 99,
                ),
              ),
              const SizedBox(width: 10),
              SkeletonText(width: 80, height: 12),
            ],
          ),
          const SizedBox(height: 18),
          // Divider (label + linha)
          Row(
            children: [
              SkeletonText(width: 96, height: 10),
              const SizedBox(width: 10),
              Expanded(
                child: SkeletonBox(height: 1, borderRadius: 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SkeletonBox(height: 102, borderRadius: 16)),
                const SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 102, borderRadius: 16)),
                const SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 102, borderRadius: 16)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SkeletonText(width: 156, height: 10),
              const SizedBox(width: 10),
              Expanded(
                child: SkeletonBox(height: 1, borderRadius: 1),
              ),
              const SizedBox(width: 10),
              SkeletonText(width: 64, height: 14),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) =>
                _dashboardSkeletonPointsComposition(context, c.maxWidth),
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

  Widget _dashboardSkeletonOperationsMiniChip(BuildContext context) {
    return SkeletonBox(
      height: 54,
      borderRadius: 12,
      width: double.infinity,
    );
  }

  /// Espelha `_buildOperationsPulseBlock` (tile com borda, não caixa sólida).
  Widget _dashboardSkeletonPulseBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SkeletonBox(width: 32, height: 32, borderRadius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 154, height: 10),
                    const SizedBox(height: 4),
                    SkeletonText(width: double.infinity, height: 12),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SkeletonText(width: 48, height: 18),
                  const SizedBox(height: 4),
                  SkeletonText(width: 40, height: 10),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SkeletonBox(
              width: double.infinity,
              height: 1,
              borderRadius: 1,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SkeletonBox(width: 32, height: 32, borderRadius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 172, height: 10),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SkeletonBox(width: 6, height: 6, borderRadius: 99),
                        const SizedBox(width: 6),
                        SkeletonText(width: 72, height: 10),
                      ],
                    ),
                  ],
                ),
              ),
              SkeletonText(width: 52, height: 22),
            ],
          ),
          const SizedBox(height: 10),
          SkeletonBox(
            height: 8,
            width: double.infinity,
            borderRadius: 99,
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonOperationsPanel(BuildContext context, double innerW) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(
            context,
            innerW,
            titleW: 168,
            trailing: SkeletonBox(width: 100, height: 30, borderRadius: 999),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SkeletonBox(height: 102, borderRadius: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SkeletonBox(height: 102, borderRadius: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SkeletonBox(height: 102, borderRadius: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Mini chips (Visitas, Chaves, Notas)
          Row(
            children: [
              Expanded(child: _dashboardSkeletonOperationsMiniChip(context)),
              const SizedBox(width: 8),
              Expanded(child: _dashboardSkeletonOperationsMiniChip(context)),
              const SizedBox(width: 8),
              Expanded(child: _dashboardSkeletonOperationsMiniChip(context)),
            ],
          ),
          const SizedBox(height: 14),
          // Section divider (label + linha)
          Row(
            children: [
              SkeletonText(width: 116, height: 10),
              const SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 1, borderRadius: 1)),
            ],
          ),
          const SizedBox(height: 10),
          _dashboardSkeletonPulseBlock(context),
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
    final accent = _dashboardAccentColor(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShellVisualTokens.inlineTileDecoration(context, accent, radius: 16),
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

  Widget _dashboardSkeletonGaugeTile(BuildContext context) {
    final accent = _dashboardAccentColor(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShellVisualTokens.inlineTileDecoration(context, accent, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SkeletonBox(width: 28, height: 28, borderRadius: 9),
              const SizedBox(width: 8),
              Expanded(child: SkeletonText(width: double.infinity, height: 10)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: SkeletonBox(
              width: double.infinity,
              height: 70,
              borderRadius: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 6, height: 6, borderRadius: 999),
              const SizedBox(width: 6),
              SkeletonText(width: 84, height: 9),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonMatchesTile(BuildContext context) {
    final accent = const Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShellVisualTokens.inlineTileDecoration(context, accent, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SkeletonBox(width: 24, height: 24, borderRadius: 9),
              const SizedBox(width: 8),
              Expanded(child: SkeletonText(width: double.infinity, height: 10)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 88, height: 32, borderRadius: 8),
                const SizedBox(height: 8),
                SkeletonText(width: 132, height: 11),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: SkeletonBox(height: 5, borderRadius: 99)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonConversionPanel(BuildContext context, double innerW) {
    final wideRow = innerW >= 460;
    final mediumRow = innerW >= 320;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSkeletonFlatHeader(
            context,
            innerW,
            titleW: 206,
            trailing: SkeletonBox(width: 108, height: 30, borderRadius: 999),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          if (wideRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: _dashboardSkeletonGaugeTile(context)),
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: _dashboardSkeletonGaugeTile(context)),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: _dashboardSkeletonMatchesTile(context)),
                ],
              ),
            )
          else if (mediumRow) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _dashboardSkeletonGaugeTile(context)),
                  const SizedBox(width: 10),
                  Expanded(child: _dashboardSkeletonGaugeTile(context)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _dashboardSkeletonMatchesTile(context),
          ] else ...[
            _dashboardSkeletonGaugeTile(context),
            const SizedBox(height: 10),
            _dashboardSkeletonGaugeTile(context),
            const SizedBox(height: 10),
            _dashboardSkeletonMatchesTile(context),
          ],
        ],
      ),
    );
  }

  Widget _dashboardSkeletonAchievements(BuildContext context, double w) {
    final itemW = w >= 900 ? (w - 60) / 4 : w >= 620 ? (w - 40) / 3 : (w - 12) / 2;
    final accent = _dashboardAccentColor(context);
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
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: ShellVisualTokens.inlineTileDecoration(
                    context,
                    accent,
                    radius: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 30, height: 30, borderRadius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              width: double.infinity,
                              height: 14,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 6),
                            SkeletonText(
                              width: double.infinity,
                              height: 14,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
            trailing: SkeletonBox(width: 124, height: 34, borderRadius: 999),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: 44, height: 3, borderRadius: 3),
          const SizedBox(height: 14),
          ...List.generate(
            4,
            (i) => Padding(
              padding: EdgeInsets.only(bottom: i == 3 ? 0 : 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context).withValues(
                      alpha: 0.42,
                    ),
                  ),
                  color: ThemeHelpers.cardBackgroundColor(context).withValues(
                    alpha: 0.42,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SkeletonBox(width: 56, height: 70, borderRadius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SkeletonBox(
                                width: 64,
                                height: 20,
                                borderRadius: 8,
                              ),
                              const SizedBox(width: 6),
                              SkeletonBox(
                                width: 78,
                                height: 20,
                                borderRadius: 8,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SkeletonText(
                            width: double.infinity,
                            height: 14,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SkeletonBox(
                                width: 13,
                                height: 13,
                                borderRadius: 4,
                              ),
                              const SizedBox(width: 4),
                              SkeletonText(width: 52, height: 11),
                              const SizedBox(width: 12),
                              SkeletonBox(
                                width: 13,
                                height: 13,
                                borderRadius: 4,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: SkeletonText(
                                  width: min(140.0, innerW * 0.4),
                                  height: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    SkeletonBox(width: 28, height: 28, borderRadius: 999),
                  ],
                ),
              ),
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

  /// Hero do dashboard — "populado" com contexto vivo do dia.
  ///
  /// Reformulado pra deixar de ser uma saudação magra e virar um painel
  /// editorial denso de informação contextual:
  ///
  /// - **Avatar real do usuário** quando disponível (fallback: monograma
  ///   accent gradient com a primeira letra do nome)
  /// - **Eyebrow `PAINEL · HH:MM` com clock vivo** que atualiza em
  ///   tempo real (sub-widget `_HeroLiveClock` com Timer.periodic)
  /// - **Saudação** dinâmica + nome
  /// - **Subtitle de role** formatado (ex.: "Master · Corretor")
  /// - **Spotlight do próximo agendamento iminente** (se houver):
  ///   destaca a próxima visita/reunião com hora + título + cliente.
  ///   Quando não há nada nos próximos compromissos, mostra um
  ///   empty-state contextual ("Nada na agenda iminente").
  /// - **Quick KPI strip** com 4 mini-pills inline mostrando contagens
  ///   chave (Imóveis · Clientes · Agendamentos · Tarefas) com ícones
  ///   próprios e cores semânticas
  /// - **Insight panel** (já existia) de variação % vs período anterior
  /// - **Pill de período ativo** + botões Atualizar/Filtros
  ///
  /// Removidas as pills antigas de "Comparação" e "Métrica" — não
  /// fazem mais parte do filtro (eram filtros sem efeito visual).
  Widget _buildGreeting(BuildContext context, ThemeData theme) {
    final user = _dashboardData?.user;
    final userName = user?.name ?? 'Usuário';
    final firstName =
        userName.trim().isEmpty ? 'Usuário' : userName.trim().split(' ').first;
    final performance = _dashboardData?.performance;
    final stats = _dashboardData?.stats;
    final upcomingAppointments =
        _dashboardData?.upcomingAppointments ?? const <DashboardAppointment>[];
    final accent = _dashboardAccentColor(context);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final actionsTop = w >= 640;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── TOP ROW: avatar + eyebrow/saudação + ações ──────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroAvatar(
                    name: userName,
                    avatarUrl: user?.avatar,
                    accent: accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Eyebrow com clock vivo
                        Row(
                          children: [
                            Text(
                              'PAINEL',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const _HeroLiveClock(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_getGreeting()}, $firstName',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            height: 1.05,
                            letterSpacing: -0.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatFullDate(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

              const SizedBox(height: 14),

              // ── SPOTLIGHT do próximo agendamento (ou empty-state) ─
              _NextAppointmentSpotlight(
                appointments: upcomingAppointments,
                accent: accent,
              ),

              const SizedBox(height: 14),

              // ── QUICK KPI strip ────────────────────────────────
              if (stats != null)
                _HeroQuickKpiStrip(
                  stats: stats,
                ),

              const SizedBox(height: 12),

              // ── Insight panel (variação % do período) ──────────
              _buildInsightPanel(context, theme, performance, stats),

              const SizedBox(height: 12),

              // ── Pill de período + ações ───────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: _buildFilterPill(
                      context,
                      Icons.date_range_outlined,
                      // Short label aqui — em telas estreitas o label
                      // longo ("Período personalizado") estourava o
                      // pill. `Flexible + ellipsis` no `_buildFilterPill`
                      // já cuida do corte; o short label só evita
                      // truncar em valores comuns ("7 dias", "30 dias").
                      _activePeriodShortLabel(),
                    ),
                  ),
                  if (!actionsTop) ...[
                    const SizedBox(width: 10),
                    _buildHeaderActions(context, theme),
                  ],
                ],
              ),
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
        color: isDark
            ? accent.withValues(alpha: 0.07)
            : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.14)
              : borderCol.withValues(alpha: 0.55),
        ),
      ),
      // `mainAxisSize: min` mas o Text precisa ser `Flexible` pra
      // permitir ellipsis quando o pill ficar dentro de `Expanded` em
      // telas estreitas — caso contrário, dá overflow horizontal
      // (caso do label "Período personalizado").
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    final moduleAccess = ModuleAccessService.instance;

    // Helper que retorna `null` quando o usuário NÃO pode acessar a rota
    // (módulo não disponível na empresa OU sem permissão de role) — assim
    // o card vira "informativo" sem ação ao toque, em vez de levar para
    // uma tela bloqueada. Respeita as regras já existentes de
    // `ModuleAccessService` (mesmas usadas pelo Drawer/módulos).
    VoidCallback? routeTap(String route) {
      if (!moduleAccess.canAccessRoutePath(route)) return null;
      return () => Navigator.of(context).pushNamed(route);
    }

    // "Comissões" ainda não tem tela própria no mobile — toque mostra um
    // toast informando que está em desenvolvimento, em vez de navegar pra
    // lugar nenhum. Quando a tela existir, basta substituir por `routeTap`.
    void onCommissionsTap() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tela de comissões em breve no app.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final cards = [
      _buildSummaryCard(
        context: context,
        theme: theme,
        title: 'Imóveis',
        value: _formatNumber(stats.myProperties),
        icon: Icons.home_work_outlined,
        color: const Color(0xFF6366F1),
        onTap: routeTap(AppRoutes.properties),
      ),
      _buildSummaryCard(
        context: context,
        theme: theme,
        title: 'Clientes',
        value: _formatNumber(stats.myClients),
        icon: Icons.groups_2_outlined,
        color: const Color(0xFF10B981),
        onTap: routeTap(AppRoutes.clients),
      ),
      _buildSummaryCard(
        context: context,
        theme: theme,
        title: 'Vistorias',
        value: _formatNumber(stats.myInspections),
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFF59E0B),
        onTap: routeTap(AppRoutes.inspections),
      ),
      _buildSummaryCard(
        context: context,
        theme: theme,
        title: 'Comissões',
        value: _formatCurrency(stats.myCommissions),
        icon: Icons.payments_outlined,
        color: const Color(0xFFEC4899),
        onTap: onCommissionsTap,
      ),
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
    final isDark = theme.brightness == Brightness.dark;

    final segments = <({
      String label,
      String value,
      IconData icon,
      Color color,
    })>[
      (
        label: 'Tarefas',
        value: _formatNumber(stats.myTasks),
        icon: Icons.assignment_turned_in_rounded,
        color: const Color(0xFF6366F1),
      ),
      (
        label: 'Agenda',
        value: _formatNumber(activityStats?.appointmentsThisMonth ?? 0),
        icon: Icons.event_available_rounded,
        color: const Color(0xFFF59E0B),
      ),
      (
        label: 'Matches',
        value: _formatNumber(stats.myMatches),
        icon: Icons.favorite_rounded,
        color: const Color(0xFF10B981),
      ),
    ];

    return _buildDashboardPanel(
      context: context,
      title: 'Operação ativa',
      eyebrow: 'RITMO DO DIA',
      icon: Icons.bolt_rounded,
      elevatedSurface: false,
      trailing: _buildOperationsPeriodPill(context, theme, isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOperationsKpiRail(context, theme, segments),
          const SizedBox(height: 10),
          _buildOperationsContextChips(context, theme, stats, activityStats),
          if (activityStats != null) ...[
            const SizedBox(height: 14),
            _buildPerformanceSectionDivider(
              context: context,
              theme: theme,
              label: 'Pulso operacional',
            ),
            const SizedBox(height: 10),
            _buildOperationsPulseBlock(context, theme, activityStats),
          ],
        ],
      ),
    );
  }

  /// Pill no header com ícone bolt + período ativo do filtro.
  Widget _buildOperationsPeriodPill(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final accent = _dashboardAccentColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.32 : 0.18),
            accent.withValues(alpha: isDark ? 0.16 : 0.09),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.2 : 0.11),
            blurRadius: isDark ? 10 : 7,
            offset: Offset(0, isDark ? 3 : 2),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: accent),
          const SizedBox(width: 4),
          Text(
            _activePeriodShortLabel(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// 3 KPI tiles (Tarefas, Agenda, Matches) — reusa o mesmo tile do Performance
  /// para coerência visual total entre painéis.
  Widget _buildOperationsKpiRail(
    BuildContext context,
    ThemeData theme,
    List<
        ({
          String label,
          String value,
          IconData icon,
          Color color,
        })> segments,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final dense = c.maxWidth < 360;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) SizedBox(width: dense ? 8 : 10),
                Expanded(
                  child: _buildPerformanceKpiTile(
                    context,
                    theme,
                    label: segments[i].label,
                    value: segments[i].value,
                    icon: segments[i].icon,
                    color: segments[i].color,
                    dense: dense,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Bloco "Pulso" — duas linhas inline dentro de um único container.
  /// Linha 1: fluxo (visitas + agendamentos no mês).
  /// Linha 2: conclusão (% concluído + barra animada + status semântico).
  Widget _buildOperationsPulseBlock(
    BuildContext context,
    ThemeData theme,
    DashboardActivityStats activityStats,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = _dashboardAccentColor(context);
    final tone = _operationsCompletionTone(activityStats.completionRate);
    final rate = (activityStats.completionRate / 100).clamp(0.0, 1.0).toDouble();
    final pctRounded = activityStats.completionRate.round();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: ShellVisualTokens.inlineTileDecoration(
        context,
        accent,
        radius: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOperationsPulseFluxRow(
            context: context,
            theme: theme,
            activityStats: activityStats,
            isDark: isDark,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    ShellVisualTokens.dashboardGlassBorder(context),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          _buildOperationsPulseCompletionRow(
            context: context,
            theme: theme,
            isDark: isDark,
            rate: rate,
            pctRounded: pctRounded,
            tone: tone,
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsPulseFluxRow({
    required BuildContext context,
    required ThemeData theme,
    required DashboardActivityStats activityStats,
    required bool isDark,
  }) {
    const cool = Color(0xFF6366F1);
    final visits = activityStats.totalVisits;
    final monthAppt = activityStats.appointmentsThisMonth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(
              colors: [
                cool.withValues(alpha: isDark ? 0.5 : 0.42),
                cool.withValues(alpha: isDark ? 0.24 : 0.22),
              ],
            ),
          ),
          child: const Icon(
            Icons.radar_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FLUXO OPERACIONAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cool.withValues(alpha: isDark ? 0.95 : 0.88),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.95,
                  fontSize: 9.5,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                monthAppt == 1
                    ? '1 agendamento este mês'
                    : '${_formatNumber(monthAppt)} agendamentos este mês',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Valor à direita: número grande + label "visitas"
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _formatNumber(visits),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              visits == 1 ? 'visita' : 'visitas',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cool.withValues(alpha: isDark ? 0.85 : 0.78),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
                fontSize: 9.5,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOperationsPulseCompletionRow({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required double rate,
    required int pctRounded,
    required ({String label, Color tone}) tone,
  }) {
    const teal = Color(0xFF14B8A6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  colors: [
                    tone.tone.withValues(alpha: isDark ? 0.5 : 0.42),
                    tone.tone.withValues(alpha: isDark ? 0.24 : 0.22),
                  ],
                ),
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CONCLUSÃO DE TAREFAS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone.tone.withValues(alpha: isDark ? 0.95 : 0.88),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.95,
                      fontSize: 9.5,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.tone,
                          boxShadow: [
                            BoxShadow(
                              color: tone.tone.withValues(
                                alpha: isDark ? 0.5 : 0.28,
                              ),
                              blurRadius: isDark ? 4 : 3,
                              spreadRadius: isDark ? 0 : -0.5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tone.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone.tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          fontSize: 9.5,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$pctRounded',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      height: 1,
                    ),
                  ),
                  Text(
                    '%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tone.tone.withValues(alpha: isDark ? 0.95 : 0.85),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Barra de progresso animada com glow
        SizedBox(
          height: 8,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: rate),
                    duration: const Duration(milliseconds: 750),
                    curve: Curves.easeOutCubic,
                    builder: (context, anim, _) => FractionallySizedBox(
                      widthFactor: anim,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              teal.withValues(alpha: 0.95),
                              tone.tone.withValues(alpha: 0.95),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tone.tone.withValues(
                                alpha: isDark ? 0.32 : 0.18,
                              ),
                              blurRadius: isDark ? 6 : 5,
                              offset: Offset(0, isDark ? 2 : 1),
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: isDark ? 0.1 : 0.06),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.32 : 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.95)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: isDark ? 0.92 : 0.82),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.85,
                    fontSize: 9.5,
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

  Widget _buildPerformanceCard(BuildContext context, ThemeData theme) {
    final performance = _dashboardData?.performance;
    final gamification =
        _dashboardData?.gamification ?? DashboardGamification.empty();
    if (performance == null) return const SizedBox.shrink();

    final growthPositive = performance.growthPercentage >= 0;
    final growthColor =
        growthPositive ? AppColors.status.success : AppColors.status.error;
    final accent = _dashboardAccentColor(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildDashboardPanel(
      context: context,
      title: 'Performance mensal',
      eyebrow: 'META · PROJEÇÃO · RANKING',
      icon: Icons.query_stats_rounded,
      elevatedSurface: false,
      trailing: _buildPerformanceGrowthPill(
        theme: theme,
        growthPercentage: performance.growthPercentage,
        positive: growthPositive,
        color: growthColor,
        isDark: isDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPerformanceFinanceHero(context, theme, performance, accent),
          const SizedBox(height: 18),
          _buildPerformanceSectionDivider(
            context: context,
            theme: theme,
            label: 'KPIs do período',
          ),
          const SizedBox(height: 12),
          _buildPerformanceKpiRail(context, theme, performance, gamification),
          const SizedBox(height: 18),
          _buildPerformanceSectionDivider(
            context: context,
            theme: theme,
            label: 'Composição de pontos',
            trailing: _buildPerformanceTotalPointsTag(
              theme: theme,
              points: gamification.currentPoints,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),
          _buildPointsCompositionRibbon(
            context,
            theme,
            gamification.pointsBreakdown,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceGrowthPill({
    required ThemeData theme,
    required double growthPercentage,
    required bool positive,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: isDark ? 0.34 : 0.2),
            color.withValues(alpha: isDark ? 0.18 : 0.1),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.22 : 0.11),
            blurRadius: isDark ? 10 : 7,
            offset: Offset(0, isDark ? 3 : 2),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 5),
          Text(
            '${growthPercentage.toStringAsFixed(1)}%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceTotalPointsTag({
    required ThemeData theme,
    required int points,
    required bool isDark,
  }) {
    const cool = Color(0xFF06B6D4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatNumber(points),
          style: theme.textTheme.titleSmall?.copyWith(
            color: cool.withValues(alpha: isDark ? 0.95 : 0.9),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'pts',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cool.withValues(alpha: isDark ? 0.7 : 0.65),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceSectionDivider({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10,
            height: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ShellVisualTokens.dashboardGlassBorder(context),
                  ShellVisualTokens.dashboardGlassBorder(context).withValues(
                    alpha: 0.0,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing,
        ],
      ],
    );
  }

  /// Hero financeiro INLINE — sem container envolvente, foco em hierarquia
  /// tipográfica e barras horizontais comparando ciclos.
  Widget _buildPerformanceFinanceHero(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance performance,
    Color accent,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    const cool = Color(0xFF6366F1);
    final maxVol = max(max(performance.thisMonth, performance.lastMonth), 1.0);
    final fThis = (performance.thisMonth / maxVol).clamp(0.0, 1.0);
    final fLast = (performance.lastMonth / maxVol).clamp(0.0, 1.0);
    final delta = performance.thisMonth - performance.lastMonth;

    final headline = theme.textTheme.headlineLarge?.copyWith(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w900,
      letterSpacing: -1.4,
      height: 1.0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? 0.6 : 0.32),
                    blurRadius: isDark ? 6 : 5,
                    spreadRadius: isDark ? 0 : -1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'VOLUME NO PERÍODO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                fontSize: 10,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatCurrency(performance.thisMonth),
                  style: headline,
                ),
              ),
            ),
            if (delta.abs() > 0.5) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${delta >= 0 ? '+' : '−'}${_formatCurrency(delta.abs())}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: delta >= 0
                        ? AppColors.status.success
                        : AppColors.status.error,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _buildPerformanceCompareRow(
          context: context,
          theme: theme,
          label: 'Atual',
          value: performance.thisMonth,
          fraction: fThis,
          color: accent,
          isDark: isDark,
          highlighted: true,
        ),
        const SizedBox(height: 8),
        _buildPerformanceCompareRow(
          context: context,
          theme: theme,
          label: 'Anterior',
          value: performance.lastMonth,
          fraction: fLast,
          color: cool,
          isDark: isDark,
          highlighted: false,
        ),
      ],
    );
  }

  /// Linha comparativa: label · barra horizontal animada · valor.
  Widget _buildPerformanceCompareRow({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required double value,
    required double fraction,
    required Color color,
    required bool isDark,
    required bool highlighted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlighted
                  ? ThemeHelpers.textColor(context)
                  : ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: color.withValues(alpha: isDark ? 0.1 : 0.07),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 720),
                      curve: Curves.easeOutCubic,
                      builder: (context, anim, _) => FractionallySizedBox(
                        widthFactor: anim,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: highlighted ? 0.95 : 0.7),
                                color.withValues(alpha: highlighted ? 0.65 : 0.45),
                              ],
                            ),
                            boxShadow: highlighted
                                ? [
                                    BoxShadow(
                                      color: color.withValues(
                                        alpha: isDark ? 0.34 : 0.2,
                                      ),
                                      blurRadius: isDark ? 8 : 6,
                                      offset: Offset(0, isDark ? 2 : 1),
                                      spreadRadius: -2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88),
          child: Text(
            _formatCurrency(value),
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
              color: highlighted
                  ? ThemeHelpers.textColor(context)
                  : ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceKpiRail(
    BuildContext context,
    ThemeData theme,
    DashboardPerformance performance,
    DashboardGamification gamification,
  ) {
    final tiles = <({
      String label,
      String value,
      String? sub,
      IconData icon,
      Color color,
    })>[
      (
        label: 'Ranking',
        value: '#${performance.ranking}',
        sub: performance.totalUsers > 0
            ? 'de ${_formatNumber(performance.totalUsers)}'
            : null,
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFFF59E0B),
      ),
      (
        label: 'Nível',
        value: '${gamification.level}',
        sub: 'corretor',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      (
        label: 'Pontos',
        value: _formatNumber(gamification.currentPoints),
        sub: 'no período',
        icon: Icons.stars_rounded,
        color: const Color(0xFF06B6D4),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final dense = c.maxWidth < 360;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(width: dense ? 8 : 10),
                Expanded(
                  child: _buildPerformanceKpiTile(
                    context,
                    theme,
                    label: tiles[i].label,
                    value: tiles[i].value,
                    sub: tiles[i].sub,
                    icon: tiles[i].icon,
                    color: tiles[i].color,
                    dense: dense,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPerformanceKpiTile(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required String value,
    String? sub,
    required IconData icon,
    required Color color,
    required bool dense,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        dense ? 11 : 13,
        dense ? 11 : 12,
        dense ? 11 : 13,
        dense ? 11 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.2 : 0.12),
            color.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.36 : 0.34),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.065),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                  spreadRadius: -2,
                ),
              ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -16,
            child: IgnorePointer(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: isDark ? 0.1 : 0.07),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(dense ? 6 : 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: isDark ? 0.5 : 0.42),
                          color.withValues(alpha: isDark ? 0.24 : 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: dense ? 14 : 16,
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color.withValues(alpha: isDark ? 0.95 : 0.9),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.95,
                      fontSize: 9.5,
                      height: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 10 : 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    height: 1,
                  ),
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
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

    final entries = <({int v, Color c, String l})>[
      (v: breakdown.sales, c: AppColors.status.success, l: 'Vendas'),
      (v: breakdown.rentals, c: const Color(0xFFEC4899), l: 'Aluguéis'),
      (v: breakdown.clients, c: _dashboardAccentColor(context), l: 'Clientes'),
      (v: breakdown.appointments, c: const Color(0xFFF59E0B), l: 'Agendamentos'),
      (v: breakdown.tasks, c: const Color(0xFF8B5CF6), l: 'Tarefas'),
      (v: breakdown.other, c: const Color(0xFF64748B), l: 'Outros'),
    ];

    if (total == 0) {
      return _buildPointsCompositionEmpty(context, theme);
    }

    final active = entries.where((e) => e.v > 0).toList();
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barra única em camadas (track + segmentos com gradiente + glow sutil).
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: ShellVisualTokens.dashboardGlassBorder(context),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < active.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: active[i].v,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 600 + i * 80),
                        curve: Curves.easeOutCubic,
                        builder: (context, anim, _) => Opacity(
                          opacity: anim,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  active[i].c.withValues(alpha: 0.95),
                                  active[i].c.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Lista compacta tipo "legenda quantitativa" — ordenada por valor.
        _buildPointsCompositionLegend(
          context: context,
          theme: theme,
          entries: entries,
          total: total,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildPointsCompositionLegend({
    required BuildContext context,
    required ThemeData theme,
    required List<({int v, Color c, String l})> entries,
    required int total,
    required bool isDark,
  }) {
    final sorted = [...entries]..sort((a, b) => b.v.compareTo(a.v));
    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth >= 360;
        final children = [
          for (final e in sorted)
            _buildPointsLegendRow(
              context: context,
              theme: theme,
              label: e.l,
              value: e.v,
              total: total,
              color: e.c,
              isDark: isDark,
            ),
        ];
        if (!twoCols) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          );
        }
        // 2 colunas — distribui na ordem 0,2,4 | 1,3,5
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          (i.isEven ? left : right).add(children[i]);
        }
        Widget col(List<Widget> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  items[i],
                ],
              ],
            );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: col(left)),
            const SizedBox(width: 10),
            Expanded(child: col(right)),
          ],
        );
      },
    );
  }

  Widget _buildPointsLegendRow({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required int value,
    required int total,
    required Color color,
    required bool isDark,
  }) {
    final pct = total > 0 ? (100.0 * value / total) : 0.0;
    final muted = value == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: muted ? 0.04 : (isDark ? 0.1 : 0.07)),
        border: Border.all(
          color: color.withValues(alpha: muted ? 0.14 : (isDark ? 0.32 : 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: muted ? 0.3 : 1),
                  color.withValues(alpha: muted ? 0.2 : 0.7),
                ],
              ),
              boxShadow: muted
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(
                          alpha: isDark ? 0.4 : 0.22,
                        ),
                        blurRadius: isDark ? 5 : 4,
                        spreadRadius: isDark ? 0 : -0.5,
                      ),
                    ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted
                    ? ThemeHelpers.textSecondaryColor(context)
                    : ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: -0.05,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: muted
                  ? ThemeHelpers.textSecondaryColor(context).withValues(
                      alpha: 0.7,
                    )
                  : color,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsCompositionEmpty(
    BuildContext context,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = _dashboardAccentColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        border: Border.all(
          color: ShellVisualTokens.dashboardGlassBorder(context),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bubble_chart_outlined,
            size: 22,
            color: accent.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sem pontos no período',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Conclua tarefas, agendamentos e vendas para ver a composição.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
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

  Widget _buildUpcomingAppointments(BuildContext context, ThemeData theme) {
    final appointments = _dashboardData?.upcomingAppointments ?? [];
    // Sempre limitamos o footprint visual a 3 compromissos. Mais que isso
    // vira "Ver todos os N" — a sessão NUNCA cresce com a quantidade real
    // de agendamentos, mantendo o dashboard previsível.
    const visibleLimit = 3;
    final slice = appointments.take(visibleLimit).toList();
    final isDark = theme.brightness == Brightness.dark;
    final accent = _dashboardAccentColor(context);

    return _buildDashboardPanel(
      context: context,
      title: 'Próximos compromissos',
      eyebrow: 'AGENDA',
      icon: Icons.calendar_month_outlined,
      elevatedSurface: false,
      trailing: _buildAgendaTrailingPill(
        context: context,
        theme: theme,
        accent: accent,
        isDark: isDark,
        count: appointments.length,
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.calendar),
      ),
      child: slice.isNotEmpty
          ? _buildAppointmentsTimeline(
              context: context,
              theme: theme,
              accent: accent,
              isDark: isDark,
              shown: slice,
              total: appointments.length,
            )
          : _buildAgendaEmptyState(context, theme),
    );
  }

  /// Timeline vertical premium da agenda. Cada compromisso é uma "linha"
  /// conectada à anterior por uma linha vertical sutil + bullet colorido
  /// pelo tipo. Layout editorial em 2 linhas tipográficas (header + corpo)
  /// — sem cards quadrados.
  Widget _buildAppointmentsTimeline({
    required BuildContext context,
    required ThemeData theme,
    required Color accent,
    required bool isDark,
    required List<DashboardAppointment> shown,
    required int total,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          _buildAppointmentTimelineRow(
            context: context,
            theme: theme,
            isDark: isDark,
            appointment: shown[i],
            isLast: i == shown.length - 1,
          ),
        // ── Footer "Ver todos os N compromissos" ───────────────────────
        if (total > shown.length) ...[
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.calendar),
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: Row(
                  children: [
                    // Bullet vazio só pra alinhar com a timeline acima.
                    SizedBox(
                      width: 38,
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent.withValues(
                                alpha: isDark ? 0.5 : 0.4,
                              ),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Ver todos os $total compromissos',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Linha tipográfica de compromisso (timeline). Estrutura:
  /// ```
  /// ●─── HOJE · 14h30                            [Visita]
  /// │    Visita ao apartamento Rua Gomes…
  /// │    Ana Beatriz Silva
  /// │
  /// ```
  /// Bullet 14×14 colorido pelo tipo + linha vertical 2px tracejada
  /// conectando até o próximo. Sem caixinha — fluido, premium.
  Widget _buildAppointmentTimelineRow({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required DashboardAppointment appointment,
    required bool isLast,
  }) {
    final visual = _appointmentTypeVisual(appointment.type);
    final color = visual.color;
    final proximity = _appointmentProximity(appointment.date);
    final hasClient = appointment.client.trim().isNotEmpty;

    // Header da linha — combina proximidade humanizada + horário em um
    // único label uppercase estilizado: "HOJE · 14:30" / "AMANHÃ · 09:00".
    String headerLabel;
    if (proximity != null) {
      headerLabel = appointment.time.trim().isNotEmpty
          ? '${proximity.label.toUpperCase()} · ${appointment.time}'
          : proximity.label.toUpperCase();
    } else {
      final dateChip = _appointmentDateChip(appointment.date);
      headerLabel = appointment.time.trim().isNotEmpty
          ? '${dateChip.day} ${dateChip.month.toUpperCase()} · ${appointment.time}'
          : '${dateChip.day} ${dateChip.month.toUpperCase()}';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => Navigator.of(context).pushNamed(
          AppRoutes.calendarDetails(appointment.id),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Coluna timeline (bullet + linha vertical) ───────────
                SizedBox(
                  width: 38,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Bullet com ring e glow
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: ThemeHelpers.cardBackgroundColor(context),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(
                                alpha: isDark ? 0.55 : 0.35,
                              ),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                      ),
                      // Linha vertical até o próximo (tracejada via
                      // gradient stops). Não desenha na última linha.
                      if (!isLast)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  color.withValues(
                                    alpha: isDark ? 0.45 : 0.32,
                                  ),
                                  ThemeHelpers.borderColor(context)
                                      .withValues(alpha: 0.5),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // ── Conteúdo da linha ────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header: proximidade · horário · pill do tipo (à dir)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              headerLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                color: color,
                                fontSize: 11,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildAppointmentTypeChip(
                            theme: theme,
                            isDark: isDark,
                            visual: visual,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Título — protagonista
                      Text(
                        appointment.title.isEmpty
                            ? '— sem título —'
                            : appointment.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.25,
                          height: 1.25,
                          color: ThemeHelpers.textColor(context),
                          fontSize: 14.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Cliente (se houver) — secundário
                      if (hasClient) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 12,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                appointment.client,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                  height: 1.25,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pílula do tipo de compromisso (Visita, Reunião, Vistoria…) —
  /// minimal, fundo tinted na cor do tipo + ícone + label.
  Widget _buildAppointmentTypeChip({
    required ThemeData theme,
    required bool isDark,
    required ({IconData icon, Color color, String label}) visual,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: visual.color.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(
          color: visual.color.withValues(alpha: isDark ? 0.32 : 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 11, color: visual.color),
          const SizedBox(width: 4),
          Text(
            visual.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: visual.color,
              fontSize: 10,
              letterSpacing: 0.1,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaTrailingPill({
    required BuildContext context,
    required ThemeData theme,
    required Color accent,
    required bool isDark,
    required int count,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 6, 9, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: accent.withValues(alpha: isDark ? 0.2 : 0.09),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.42 : 0.34),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0) ...[
                Text(
                  '$count',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent.withValues(alpha: 0.98),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                count > 0 ? 'agenda' : 'Ver agenda',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: accent.withValues(alpha: 0.95),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgendaEmptyState(BuildContext context, ThemeData theme) {
    final accent = _dashboardAccentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: ShellVisualTokens.inlineTileDecoration(
        context,
        accent,
        radius: 22,
      ),
      child: Column(
        children: [
          // Mini-calendário decorativo
          Container(
            width: 60,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.42 : 0.36),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                        spreadRadius: -4,
                      ),
                    ],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: isDark ? 0.78 : 0.92),
                        accent.withValues(alpha: isDark ? 0.55 : 0.7),
                      ],
                    ),
                  ),
                  child: const Text(
                    '— —',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Icon(
                      Icons.calendar_today_outlined,
                      size: 22,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Agenda livre por aqui',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Sem compromissos nos próximos dias.\nQue tal agendar uma visita ou reunião?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.calendar),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.78),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.32 : 0.2),
                      blurRadius: isDark ? 14 : 10,
                      offset: Offset(0, isDark ? 6 : 3),
                      spreadRadius: isDark ? -4 : -3,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Abrir agenda',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Helpers de agenda ───────────

  /// Tenta interpretar formatos vindos da API (ISO, "DD/MM[/YYYY]", "DD-MM[-YYYY]").
  DateTime? _tryParseAppointmentDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final parts = s.split(RegExp(r'[\/\-\.]'));
    if (parts.length >= 2) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (d != null && m != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        final y = parts.length >= 3
            ? (int.tryParse(parts[2]) ?? DateTime.now().year)
            : DateTime.now().year;
        return DateTime(y < 100 ? 2000 + y : y, m, d);
      }
    }
    return null;
  }

  String _appointmentMonthShort(int m) {
    const months = [
      'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
      'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
    ];
    return months[(m - 1).clamp(0, 11)];
  }

  String _appointmentWeekdayShort(int weekday) {
    const days = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  /// Retorna `(dia, mês, weekday)` para o tile de calendário; se não conseguir
  /// interpretar, devolve fallback discreto.
  ({String day, String month, String? weekday}) _appointmentDateChip(
    String raw,
  ) {
    final dt = _tryParseAppointmentDate(raw);
    if (dt != null) {
      return (
        day: dt.day.toString().padLeft(2, '0'),
        month: _appointmentMonthShort(dt.month),
        weekday: _appointmentWeekdayShort(dt.weekday),
      );
    }
    return (day: '—', month: '— —', weekday: null);
  }

  /// Pill de proximidade (Hoje / Amanhã / Em N dias / Atrasado).
  ({String label, Color color, IconData icon})? _appointmentProximity(
    String raw,
  ) {
    final dt = _tryParseAppointmentDate(raw);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;
    if (diff < 0) {
      return (
        label: 'Atrasado',
        color: const Color(0xFFF87171),
        icon: Icons.priority_high_rounded,
      );
    }
    if (diff == 0) {
      return (
        label: 'Hoje',
        color: const Color(0xFF22D3EE),
        icon: Icons.bolt_rounded,
      );
    }
    if (diff == 1) {
      return (
        label: 'Amanhã',
        color: const Color(0xFF818CF8),
        icon: Icons.schedule_rounded,
      );
    }
    if (diff <= 7) {
      return (
        label: 'Em $diff dias',
        color: const Color(0xFFA78BFA),
        icon: Icons.event_rounded,
      );
    }
    return null;
  }

  /// Ícone, cor e rótulo por tipo de compromisso.
  ({IconData icon, Color color, String label}) _appointmentTypeVisual(
    String type,
  ) {
    final t = type.toLowerCase().trim();
    if (t.contains('meeting') ||
        t.contains('reunião') ||
        t.contains('reuniao')) {
      return (
        icon: Icons.groups_2_rounded,
        color: const Color(0xFF6366F1),
        label: 'Reunião',
      );
    }
    if (t.contains('visit') || t.contains('visita')) {
      return (
        icon: Icons.directions_walk_rounded,
        color: const Color(0xFF10B981),
        label: 'Visita',
      );
    }
    if (t.contains('inspection') || t.contains('vistoria')) {
      return (
        icon: Icons.fact_check_rounded,
        color: const Color(0xFFF59E0B),
        label: 'Vistoria',
      );
    }
    if (t.contains('call') || t.contains('ligaç')) {
      return (
        icon: Icons.call_rounded,
        color: const Color(0xFF22D3EE),
        label: 'Ligação',
      );
    }
    if (t.contains('signing') || t.contains('assin')) {
      return (
        icon: Icons.draw_rounded,
        color: const Color(0xFFEC4899),
        label: 'Assinatura',
      );
    }
    if (t.contains('open_house') || t.contains('aberta')) {
      return (
        icon: Icons.meeting_room_rounded,
        color: const Color(0xFFF472B6),
        label: 'Casa aberta',
      );
    }
    return (
      icon: Icons.event_rounded,
      color: const Color(0xFF818CF8),
      label: 'Compromisso',
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

  Widget _buildGoalsContent(
    BuildContext context,
    ThemeData theme,
    DashboardMonthlyGoals goals,
  ) {
    // Dias restantes do mês — adiciona contexto motivacional ("ainda dá tempo").
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = (lastDay - now.day).clamp(0, 31);

    return LayoutBuilder(
      builder: (context, c) {
        final sideBySide = c.maxWidth >= 480 &&
            goals.sales != null &&
            goals.commissions != null;
        final tiles = <Widget>[
          if (goals.sales != null)
            _buildGoalProgress(
              context: context,
              theme: theme,
              label: 'Vendas',
              current: goals.sales!.current.toDouble(),
              target: goals.sales!.target.toDouble(),
              percentage: goals.sales!.percentage,
              icon: Icons.home_work_rounded,
            ),
          if (goals.commissions != null)
            _buildGoalProgress(
              context: context,
              theme: theme,
              label: 'Comissões',
              current: goals.commissions!.current.toDouble(),
              target: goals.commissions!.target.toDouble(),
              percentage: goals.commissions!.percentage,
              icon: Icons.payments_rounded,
              isCurrency: true,
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Footer motivacional — dias restantes.
            _buildGoalsTimelineHeader(
              context: context,
              theme: theme,
              daysLeft: daysLeft,
            ),
            const SizedBox(height: 12),
            if (sideBySide && tiles.length == 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tiles[0]),
                    const SizedBox(width: 10),
                    Expanded(child: tiles[1]),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    tiles[i],
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  /// Faixa "ainda dá tempo" no topo das metas — situa o usuário no mês
  /// (dias restantes) sem precisar abrir o calendário.
  Widget _buildGoalsTimelineHeader({
    required BuildContext context,
    required ThemeData theme,
    required int daysLeft,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = _dashboardAccentColor(context);
    const cool = Color(0xFF0891B2);

    final monthName =
        DateFormat("MMMM 'de' yyyy", 'pt_BR').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  accent.withValues(alpha: 0.12),
                  cool.withValues(alpha: 0.07),
                ]
              : [
                  accent.withValues(alpha: 0.07),
                  cool.withValues(alpha: 0.04),
                ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: daysLeft == 0
                        ? 'Último dia '
                        : (daysLeft == 1
                            ? 'Falta apenas 1 dia '
                            : 'Faltam $daysLeft dias '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.05,
                    ),
                  ),
                  TextSpan(
                    text: 'em $monthName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
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

  /// Tile de progresso de meta — gauge circular + dados textuais.
  ///
  /// Visual:
  /// - Gauge circular grande (~64px) com a porcentagem no centro
  /// - Cor dinâmica conforme progresso (vermelho/âmbar/cyan/verde)
  /// - Coluna direita: ícone tinted + label + valor atual / alvo + faltante
  /// - Estado "meta batida" (>= 100%): glow verde + label "Meta superada!"
  Widget _buildGoalProgress({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required double current,
    required double target,
    required double percentage,
    required IconData icon,
    bool isCurrency = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final color = _goalProgressColor(percentage);
    final clamped = (percentage / 100).clamp(0.0, 1.0).toDouble();
    final overShoot = percentage >= 100;
    final remaining = (target - current).clamp(0, double.infinity).toDouble();

    // Texto auxiliar — muda de tom conforme o progresso.
    final String helperText;
    if (overShoot) {
      helperText = 'Meta superada · +${(percentage - 100).toStringAsFixed(0)}%';
    } else if (remaining <= 0) {
      helperText = 'Falta zero · siga em frente';
    } else if (isCurrency) {
      helperText = 'Faltam ${_formatCurrency(remaining)}';
    } else {
      helperText = 'Faltam ${_formatNumber(remaining.toInt())}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.28),
          width: overShoot ? 1.4 : 1,
        ),
        boxShadow: overShoot
            ? [
                BoxShadow(
                  color: color.withValues(alpha: isDark ? 0.32 : 0.18),
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : (isDark
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: -6,
                    ),
                  ]),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Gauge circular ──────────────────────────────────────────────
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Anel de fundo (cor base levemente tinted)
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 7,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      color.withValues(alpha: isDark ? 0.16 : 0.12),
                    ),
                  ),
                ),
                // Anel de progresso
                SizedBox(
                  width: 70,
                  height: 70,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: clamped),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                // % no centro
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      overShoot
                          ? '✓'
                          : '${percentage.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                        letterSpacing: -0.6,
                      ),
                    ),
                    if (!overShoot)
                      Text(
                        '%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.4,
                          height: 1,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // ── Coluna direita: dados textuais ──────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                        border: Border.all(
                          color: color.withValues(alpha: isDark ? 0.38 : 0.28),
                        ),
                      ),
                      child: Icon(icon, color: color, size: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          fontSize: 9.5,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Valor atual (grande) + alvo
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: isCurrency
                              ? _formatCurrency(current)
                              : _formatNumber(current.toInt()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.4,
                            height: 1.05,
                          ),
                        ),
                        TextSpan(
                          text: '  / ${isCurrency ? _formatCurrency(target) : _formatNumber(target.toInt())}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textSecondaryColor(context),
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  helperText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 11,
                    letterSpacing: -0.05,
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

  /// Cor dinâmica do progresso de meta:
  /// - >= 100%: verde (objetivo atingido)
  /// - >=  70%: cyan (no caminho certo)
  /// - >=  40%: âmbar (atenção)
  /// - <   40%: rosa accent (alerta)
  Color _goalProgressColor(double percentage) {
    if (percentage >= 100) return const Color(0xFF10B981);
    if (percentage >= 70) return const Color(0xFF0891B2);
    if (percentage >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEC4899);
  }

  Widget _buildConversionMetrics(BuildContext context, ThemeData theme) {
    final metrics = _dashboardData?.conversionMetrics;
    if (metrics == null) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;

    // 3 indicadores: 2 taxas (gauge) + 1 contagem (matches).
    final visitsGauge = _ConversionGaugeData(
      label: 'Visitas → Vendas',
      shortLabel: 'Visitas',
      percentage: metrics.visitsToSales,
      icon: Icons.show_chart_rounded,
      baseColor: const Color(0xFF6366F1),
    );
    final clientsGauge = _ConversionGaugeData(
      label: 'Clientes → Fechados',
      shortLabel: 'Clientes',
      percentage: metrics.clientsToClosed,
      icon: Icons.handshake_rounded,
      baseColor: const Color(0xFFEC4899),
    );

    return _buildDashboardPanel(
      context: context,
      title: 'Métricas de conversão',
      eyebrow: 'EFICIÊNCIA',
      icon: Icons.insights_outlined,
      elevatedSurface: false,
      trailing: _buildConversionTrailingTag(
        theme: theme,
        gauges: [visitsGauge, clientsGauge],
        isDark: isDark,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final wideRow = w >= 460;
          final mediumRow = w >= 320;

          final gaugeVisits = _buildConversionGaugeTile(
            context: context,
            theme: theme,
            data: visitsGauge,
            isDark: isDark,
          );
          final gaugeClients = _buildConversionGaugeTile(
            context: context,
            theme: theme,
            data: clientsGauge,
            isDark: isDark,
          );
          final matchesTile = _buildConversionMatchesTile(
            context: context,
            theme: theme,
            count: metrics.matchesAccepted,
            isDark: isDark,
          );

          if (wideRow) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: gaugeVisits),
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: gaugeClients),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: matchesTile),
                ],
              ),
            );
          }
          if (mediumRow) {
            // 2 gauges em row + matches abaixo (mais compacto que 3 colunas estreitas)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: gaugeVisits),
                      const SizedBox(width: 10),
                      Expanded(child: gaugeClients),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                matchesTile,
              ],
            );
          }
          // Stretto extremo — empilha tudo
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              gaugeVisits,
              const SizedBox(height: 10),
              gaugeClients,
              const SizedBox(height: 10),
              matchesTile,
            ],
          );
        },
      ),
    );
  }

  /// Tag agregada no header — média das taxas, com tom verde/amarelo/vermelho.
  Widget _buildConversionTrailingTag({
    required ThemeData theme,
    required List<_ConversionGaugeData> gauges,
    required bool isDark,
  }) {
    final avg = gauges.isEmpty
        ? 0.0
        : gauges.map((g) => g.percentage).reduce((a, b) => a + b) /
            gauges.length;
    final tone = _conversionTone(avg);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 11, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            tone.withValues(alpha: isDark ? 0.32 : 0.18),
            tone.withValues(alpha: isDark ? 0.16 : 0.09),
          ],
        ),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: isDark ? 0.22 : 0.1),
            blurRadius: isDark ? 10 : 6,
            offset: Offset(0, isDark ? 3 : 2),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.adjust_rounded, size: 14, color: tone),
          const SizedBox(width: 5),
          Text(
            '${avg.toStringAsFixed(1)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'média',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone.withValues(alpha: 0.85),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              fontSize: 9.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Tonalidade comum a todos os indicadores de eficiência.
  Color _conversionTone(double pct) {
    if (pct >= 50) return const Color(0xFF10B981);
    if (pct >= 25) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _buildConversionGaugeTile({
    required BuildContext context,
    required ThemeData theme,
    required _ConversionGaugeData data,
    required bool isDark,
  }) {
    final tone = _conversionTone(data.percentage);
    final pct01 = (data.percentage / 100).clamp(0.0, 1.0).toDouble();
    final base = data.baseColor;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: isDark ? 0.18 : 0.1),
            base.withValues(alpha: isDark ? 0.05 : 0.04),
          ],
        ),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.32 : 0.3),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: base.withValues(alpha: 0.055),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.022),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                  spreadRadius: -1,
                ),
              ],
      ),
      child: Stack(
        children: [
          // Orbe sutil de fundo
          Positioned(
            right: -16,
            top: -22,
            child: IgnorePointer(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: base.withValues(alpha: isDark ? 0.1 : 0.065),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: [
                          base.withValues(alpha: isDark ? 0.5 : 0.42),
                          base.withValues(alpha: isDark ? 0.24 : 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      data.icon,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: base.withValues(alpha: isDark ? 0.95 : 0.88),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.85,
                        fontSize: 9.5,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Gauge semi-circular animado
              SizedBox(
                height: 70,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct01),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, anim, _) => Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ConversionGaugePainter(
                            progress: anim,
                            color: tone,
                            trackColor: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : base.withValues(alpha: 0.1),
                            tickColor: base,
                          ),
                        ),
                      ),
                      // Número grande no centro do arco
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(anim * 100).toStringAsFixed(1)}%',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.85,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Mini-status com bolinha tonal e label semântico
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(
                            alpha: isDark ? 0.55 : 0.32,
                          ),
                          blurRadius: isDark ? 5 : 4,
                          spreadRadius: isDark ? 0 : -0.5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _conversionStatusLabel(data.percentage),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      fontSize: 9.5,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _conversionStatusLabel(double pct) {
    if (pct >= 50) return 'EXCELENTE';
    if (pct >= 25) return 'EM RITMO';
    if (pct > 0) return 'PRECISA ATENÇÃO';
    return 'SEM REGISTRO';
  }

  Widget _buildConversionMatchesTile({
    required BuildContext context,
    required ThemeData theme,
    required int count,
    required bool isDark,
  }) {
    const base = Color(0xFF10B981);
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: isDark ? 0.2 : 0.12),
            base.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.36 : 0.3),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: base.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.022),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                  spreadRadius: -1,
                ),
              ],
      ),
      child: Stack(
        children: [
          // Heart anelado decorativo
          Positioned(
            right: -10,
            bottom: -14,
            child: IgnorePointer(
              child: Icon(
                Icons.favorite_rounded,
                size: 96,
                color: base.withValues(alpha: isDark ? 0.06 : 0.045),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: [
                          base.withValues(alpha: isDark ? 0.5 : 0.42),
                          base.withValues(alpha: isDark ? 0.24 : 0.22),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MATCHES ACEITOS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: base.withValues(alpha: isDark ? 0.95 : 0.88),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.85,
                        fontSize: 9.5,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Espelha a altura do gauge para alinhar com gauges (70px da painel + ~20 do label/dot)
              SizedBox(
                height: 70,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: count.toDouble()),
                          duration: const Duration(milliseconds: 750),
                          curve: Curves.easeOutCubic,
                          builder: (context, anim, _) => Text(
                            _formatNumber(anim.round()),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.6,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 1
                            ? '1 conexão confirmada'
                            : '${_formatNumber(count)} conexões confirmadas',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.05,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Mini-barra de "intensidade" (visual sutil — saturada conforme cresce).
              _buildMatchesIntensityBar(
                context: context,
                count: count,
                base: base,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Barrinha de intensidade — 0 a 5 segmentos com base no count.
  Widget _buildMatchesIntensityBar({
    required BuildContext context,
    required int count,
    required Color base,
    required bool isDark,
  }) {
    const segments = 5;
    final lit = count <= 0
        ? 0
        : count >= 50
            ? segments
            : count >= 25
                ? 4
                : count >= 10
                    ? 3
                    : count >= 5
                        ? 2
                        : 1;
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: i < lit ? 1.0 : 0.0),
              duration: Duration(milliseconds: 350 + i * 90),
              curve: Curves.easeOutCubic,
              builder: (context, anim, _) => Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: base.withValues(alpha: isDark ? 0.08 : 0.07),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: anim,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              base.withValues(alpha: 0.95),
                              base.withValues(alpha: 0.6),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: base.withValues(
                                alpha: isDark ? 0.4 : 0.2,
                              ),
                              blurRadius: isDark ? 6 : 4,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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
    VoidCallback? onTap,
  }) {
    // Altura fixa: filhos de `Wrap` têm altura máxima ilimitada — `Spacer`/`Expanded`
    // no eixo vertical quebram o layout e podem deixar o dashboard em branco.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final figureStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w900,
      color: ThemeHelpers.textColor(context),
      letterSpacing: -0.85,
      height: 1.05,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final card = Container(
      height: 128,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.26 : 0.16),
            color.withValues(alpha: isDark ? 0.07 : 0.06),
          ],
        ),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.42 : 0.46),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                  spreadRadius: -8,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.028),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                  spreadRadius: -2,
                ),
              ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.35 : 0.65),
                    color.withValues(alpha: 0.95),
                    color.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -18,
            top: -22,
            child: IgnorePointer(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: isDark ? 0.12 : 0.085),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.14 : 0.5,
                          ),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(
                              alpha: isDark ? 0.22 : 0.12,
                            ),
                            blurRadius: isDark ? 10 : 7,
                            offset: Offset(0, isDark ? 4 : 2),
                            spreadRadius: isDark ? 0 : -1,
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: isDark ? 0.52 : 0.44),
                              color.withValues(alpha: isDark ? 0.24 : 0.22),
                            ],
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.96),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.north_east_rounded,
                      size: 18,
                      color: color.withValues(alpha: isDark ? 0.55 : 0.42),
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
                        style: figureStyle,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.08,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    // Quando há `onTap`, envolvemos em Material+InkWell pra ganhar ripple
    // e indicar visualmente que o card é interativo. ClipRRect respeita o
    // borderRadius original do Container.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: color.withValues(alpha: 0.18),
          highlightColor: color.withValues(alpha: 0.08),
          child: card,
        ),
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
            color: isDark ? color.withOpacity(0.24) : color.withValues(alpha: 0.18),
            blurRadius: isDark ? 16 : 11,
            offset: Offset(0, isDark ? 8 : 4),
            spreadRadius: isDark ? 0 : -1,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
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

  /// Rótulo curto para chips e pills (evita corte em telas estreitas).
  String _activePeriodShortLabel() {
    switch (_filters.dateRange) {
      case 'today':
        return 'Hoje';
      case '7d':
        return '7 dias';
      case '30d':
        return '30 dias';
      case '90d':
        return '90 dias';
      case '1y':
        return '1 ano';
      case 'custom':
        return 'Personalizado';
      default:
        return 'Atual';
    }
  }

}

/// Dados de um gauge da seção Métricas de conversão.
class _ConversionGaugeData {
  final String label;
  final String shortLabel;
  final double percentage;
  final IconData icon;
  final Color baseColor;

  const _ConversionGaugeData({
    required this.label,
    required this.shortLabel,
    required this.percentage,
    required this.icon,
    required this.baseColor,
  });
}

/// Pintor do gauge semi-circular usado em "Métricas de conversão".
///
/// - Track sutil (mesma curvatura) com strokeCap arredondado.
/// - Arco de progresso com gradiente sweep da cor "tonal".
/// - Pontos de referência nas extremidades (0% e 100%) para reforçar leitura.
class _ConversionGaugePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final Color tickColor;

  _ConversionGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.tickColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final cx = size.width / 2;
    final cy = size.height - 6;
    final radius = min(size.width / 2, size.height) - strokeWidth / 2 - 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Track (semi-círculo de pi até 2*pi)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, pi, pi, false, trackPaint);

    // Arco de progresso com SweepGradient da cor (com ponta arredondada)
    if (progress > 0.001) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: pi,
          endAngle: pi * 2,
          colors: [
            color.withValues(alpha: 0.55),
            color,
          ],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, pi, pi * progress, false, progressPaint);

      // Ponteiro discreto na extremidade do progresso (efeito "led" final).
      final endAngle = pi + pi * progress;
      final endX = cx + radius * cos(endAngle);
      final endY = cy + radius * sin(endAngle);
      final knobOuter = Paint()..color = color.withValues(alpha: 0.18);
      canvas.drawCircle(Offset(endX, endY), strokeWidth * 0.95, knobOuter);
      final knobInner = Paint()..color = color;
      canvas.drawCircle(Offset(endX, endY), strokeWidth * 0.32, knobInner);
    }

    // Ticks nas extremidades (0% à esquerda, 100% à direita)
    final tickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - radius, cy), 1.6, tickPaint);
    canvas.drawCircle(Offset(cx + radius, cy), 1.6, tickPaint);
  }

  @override
  bool shouldRepaint(covariant _ConversionGaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

// ═══════════════════════════════════════════════════════════════════
// HERO COMPONENTS — sub-widgets do `_buildGreeting`
// ═══════════════════════════════════════════════════════════════════

/// Avatar do hero — usa foto real se disponível, senão monograma
/// gradient accent com a primeira letra do nome.
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({
    required this.name,
    required this.avatarUrl,
    required this.accent,
  });

  final String name;
  final String? avatarUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final hasUrl = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: hasUrl
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, const Color(0xFF7C3AED), 0.45) ?? accent,
                ],
              ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: hasUrl
            ? Image.network(
                avatarUrl!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _MonogramFallback(
                  initials: initials,
                ),
              )
            : _MonogramFallback(initials: initials),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _MonogramFallback extends StatelessWidget {
  const _MonogramFallback({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Clock vivo no eyebrow do hero — atualiza a cada 30s.
class _HeroLiveClock extends StatefulWidget {
  const _HeroLiveClock();

  @override
  State<_HeroLiveClock> createState() => _HeroLiveClockState();
}

class _HeroLiveClockState extends State<_HeroLiveClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // 30s é resolução suficiente — clock minute-precision sem custo
    // alto de redraws. Quando a janela mudar de minuto, re-renderiza.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Text(
      timeStr,
      style: theme.textTheme.labelSmall?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Spotlight do próximo agendamento iminente — destaque editorial
/// pra o compromisso mais próximo do user.
///
/// Exibe horário grande à esquerda, título do compromisso, cliente
/// e tipo. Quando não há agendamentos próximos, mostra um empty-state
/// contextual com ícone discreto.
class _NextAppointmentSpotlight extends StatelessWidget {
  const _NextAppointmentSpotlight({
    required this.appointments,
    required this.accent,
  });

  final List<DashboardAppointment> appointments;
  final Color accent;

  /// Próximo compromisso = primeiro item da lista (já vem ordenado por
  /// data/hora pelo backend).
  DashboardAppointment? get _next =>
      appointments.isEmpty ? null : appointments.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final next = _next;

    if (next == null) {
      // Empty state — discreto, sem container destacado
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_available_rounded,
              size: 18,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nada na agenda iminente · aproveite pra prospectar',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final timeText = next.time.isNotEmpty ? next.time : '—';
    final dateText = _formatRelativeDate(next.date);
    final typeText = _formatType(next.type);
    final hasClient = next.client.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Fundo sutilmente tingido accent — bloco de "atenção"
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Coluna de tempo grande à esquerda
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: -0.6,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateText.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),

          // Divisor vertical sutil
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: accent.withValues(alpha: 0.25),
          ),

          // Coluna de detalhes
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(_iconForType(next.type), size: 13, color: accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        typeText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  next.title.isNotEmpty ? next.title : 'Compromisso',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasClient) ...[
                  const SizedBox(height: 2),
                  Text(
                    next.client,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeDate(String iso) {
    if (iso.isEmpty) return 'Próximo';
    try {
      final d = DateTime.parse(iso);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(d.year, d.month, d.day);
      final diff = target.difference(today).inDays;
      if (diff == 0) return 'Hoje';
      if (diff == 1) return 'Amanhã';
      if (diff < 7) return DateFormat('EEEE', 'pt_BR').format(d);
      return DateFormat('d MMM', 'pt_BR').format(d);
    } catch (_) {
      return 'Próximo';
    }
  }

  String _formatType(String type) {
    final t = type.trim().toLowerCase();
    return switch (t) {
      'visit' => 'Visita',
      'meeting' => 'Reunião',
      'call' => 'Ligação',
      'inspection' => 'Vistoria',
      'signing' => 'Assinatura',
      _ => t.isEmpty ? 'Compromisso' : '${t[0].toUpperCase()}${t.substring(1)}',
    };
  }

  IconData _iconForType(String type) {
    final t = type.trim().toLowerCase();
    return switch (t) {
      'visit' => Icons.directions_walk_rounded,
      'meeting' => Icons.groups_rounded,
      'call' => Icons.phone_rounded,
      'inspection' => Icons.fact_check_outlined,
      'signing' => Icons.draw_rounded,
      _ => Icons.event_rounded,
    };
  }
}

/// Linha de "manchete" editorial com KPIs do user.
///
/// 4 métricas escolhidas pra **não duplicar** os cards principais
/// embaixo do dashboard (Imóveis, Clientes, Vistorias, Comissões):
///
///   12.5%       3            3            5
///   CONVERSÃO   MATCHES      AGENDA       TAREFAS
///   ────────    ──────       ──────       ───────
///
/// Cada coluna divide o espaço igualmente (`Expanded`), com:
/// - Valor grande em peso 900, com a cor temática da categoria
///   (suporta `int` ou `double` formatado em %)
/// - Label uppercase fina abaixo
/// - Linha accent fina sob o label como assinatura visual
/// - Separadores verticais sutis entre colunas
class _HeroQuickKpiStrip extends StatelessWidget {
  const _HeroQuickKpiStrip({
    required this.stats,
  });

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final items = <_QuickKpi>[
      _QuickKpi(
        accent: const Color(0xFF0EA5E9), // azul — carteira de imóveis
        label: 'Imóveis',
        value: '${stats.myProperties}',
      ),
      _QuickKpi(
        accent: const Color(0xFF14B8A6), // teal — carteira de clientes
        label: 'Clientes',
        value: '${stats.myClients}',
      ),
      _QuickKpi(
        accent: const Color(0xFFF59E0B), // âmbar — agenda
        label: 'Agenda',
        value: '${stats.myAppointments}',
      ),
      _QuickKpi(
        accent: const Color(0xFF8B5CF6), // roxo — tarefas
        label: 'Tarefas',
        value: '${stats.myTasks}',
      ),
    ];

    final divColor = ThemeHelpers.borderLightColor(context)
        .withValues(alpha: 0.6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 38,
              color: divColor,
            ),
          Expanded(child: items[i].render(context)),
        ],
      ],
    );
  }
}

class _QuickKpi {
  const _QuickKpi({
    required this.accent,
    required this.label,
    required this.value,
  });

  final Color accent;
  final String label;

  /// Valor já formatado como string (suporta int "12", double "12.5%",
  /// "—" para ausente). O formatting é responsabilidade do caller.
  final String value;

  Widget render(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Valor grande — protagonista visual de cada coluna
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: -0.6,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Label uppercase fina — como "rótulo" do valor
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 1.4,
              fontSize: 9.5,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Linha accent fina — assinatura visual sutil
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
