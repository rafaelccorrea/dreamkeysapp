import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/dashboard_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../notifications/widgets/notification_center.dart';

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
  bool _isLoading = true;
  DashboardResponse? _dashboardData;
  String? _errorMessage;

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
      final response = await DashboardService.instance.getUserDashboard();

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Dream Keys',
      currentBottomNavIndex: 0,
      userName: _dashboardData?.user.name,
      userEmail: _dashboardData?.user.email,
      userAvatar: _dashboardData?.user.avatar,
      actions: [
        const NotificationCenter(),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadDashboardData,
          tooltip: 'Atualizar',
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Cabeçalho com Saudação
                    _buildGreeting(context, theme),
                    const SizedBox(height: 32),

                    // 2. Card de Performance
                    if (_dashboardData != null)
                      _buildPerformanceCard(context, theme),
                    if (_dashboardData != null) const SizedBox(height: 32),

                    // 3. Seção de Conquistas
                    if (_dashboardData != null &&
                        _dashboardData!.gamification.achievements.isNotEmpty)
                      _buildAchievementsSection(context, theme),
                    if (_dashboardData != null &&
                        _dashboardData!.gamification.achievements.isNotEmpty)
                      const SizedBox(height: 32),

                    // 4. Cards de Estatísticas Principais
                    _buildStatsCards(context, theme),
                    const SizedBox(height: 32),

                    // 5. Seção de Atividades
                    if (_dashboardData != null)
                      _buildActivitiesSection(context, theme),
                    if (_dashboardData != null) const SizedBox(height: 32),

                    // 6. Metas Mensais
                    if (_dashboardData != null)
                      _buildMonthlyGoalsSection(context, theme),
                    if (_dashboardData != null) const SizedBox(height: 32),

                    // 7. Métricas de Conversão
                    if (_dashboardData != null)
                      _buildConversionMetrics(context, theme),
                    if (_dashboardData != null) const SizedBox(height: 32),

                    // 8. Atividades Recentes
                    if (_dashboardData != null)
                      _buildRecentActivities(context, theme),
                    if (_dashboardData != null) const SizedBox(height: 32),

                    // 9. Próximos Agendamentos
                    if (_dashboardData != null)
                      _buildUpcomingAppointments(context, theme),
                  ],
                ),
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
                    SkeletonText(width: 200, height: 24, margin: const EdgeInsets.only(bottom: 8)),
                    SkeletonText(width: 180, height: 16, margin: const EdgeInsets.only(bottom: 8)),
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
                SkeletonText(width: 180, height: 20, margin: const EdgeInsets.only(bottom: 16)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(width: 100, height: 16, margin: const EdgeInsets.only(bottom: 8)),
                          SkeletonText(width: 80, height: 32),
                        ],
                      ),
                    ),
                    SkeletonBox(width: 60, height: 60, borderRadius: 30),
                  ],
                ),
                const SizedBox(height: 16),
                SkeletonText(width: double.infinity, height: 8, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Skeleton dos cards de estatísticas
          SkeletonText(width: 120, height: 20, margin: const EdgeInsets.only(bottom: 16)),
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
          SkeletonText(width: 120, height: 20, margin: const EdgeInsets.only(bottom: 16)),
          SkeletonList(itemCount: 3, itemHeight: 80),
          const SizedBox(height: 32),

          // Skeleton de metas mensais
          SkeletonText(width: 120, height: 20, margin: const EdgeInsets.only(bottom: 16)),
          SkeletonCard(
            height: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 100, height: 16, margin: const EdgeInsets.only(bottom: 12)),
                SkeletonText(width: double.infinity, height: 8, borderRadius: 4, margin: const EdgeInsets.only(bottom: 8)),
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

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getGreeting()}, ${userName.split(' ').first}! 👋',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aqui está um resumo das suas atividades',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatFullDate(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            // TODO: Implementar drawer de filtros
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Filtros em breve'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          tooltip: 'Filtros',
        ),
      ],
    );
  }

  Widget _buildAchievementsSection(BuildContext context, ThemeData theme) {
    final achievements = _dashboardData?.gamification.achievements ?? [];
    if (achievements.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Conquistas'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final crossAxisCount = screenWidth > 600 ? 3 : 2;
            final spacing = screenWidth > 600 ? 16.0 : 12.0;
            final childAspectRatio = screenWidth > 600 ? 1.1 : 1.2;
            
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: achievements.length > 6 ? 6 : achievements.length,
              itemBuilder: (context, index) {
            final achievement = achievements[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: ThemeHelpers.shadowColor(context),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(achievement.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(
                    achievement.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatsCards(BuildContext context, ThemeData theme) {
    final stats = _dashboardData?.stats;
    if (stats == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isTablet = screenWidth > 600;
        final isDesktop = screenWidth > 900;
        
        // Em telas grandes, mostrar 4 cards em uma linha
        if (isDesktop) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Estatísticas'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Imóveis',
                      value: _formatNumber(stats.myProperties),
                      icon: Icons.home_outlined,
                      color: const Color(0xFF3b82f6),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Clientes',
                      value: _formatNumber(stats.myClients),
                      icon: Icons.people_outlined,
                      color: const Color(0xFF10b981),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Vistorias',
                      value: _formatNumber(stats.myInspections),
                      icon: Icons.task_alt_outlined,
                      color: const Color(0xFFf59e0b),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Comissões',
                      value: _formatCurrency(stats.myCommissions),
                      icon: Icons.attach_money_outlined,
                      color: const Color(0xFFec4899),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        
        // Em tablets, mostrar 2x2
        if (isTablet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Estatísticas'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Imóveis',
                      value: _formatNumber(stats.myProperties),
                      icon: Icons.home_outlined,
                      color: const Color(0xFF3b82f6),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Clientes',
                      value: _formatNumber(stats.myClients),
                      icon: Icons.people_outlined,
                      color: const Color(0xFF10b981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Vistorias',
                      value: _formatNumber(stats.myInspections),
                      icon: Icons.task_alt_outlined,
                      color: const Color(0xFFf59e0b),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      context: context,
                      theme: theme,
                      title: 'Comissões',
                      value: _formatCurrency(stats.myCommissions),
                      icon: Icons.attach_money_outlined,
                      color: const Color(0xFFec4899),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        
        // Em mobile, manter 2x2
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estatísticas',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    context: context,
                    theme: theme,
                    title: 'Imóveis',
                    value: _formatNumber(stats.myProperties),
                    icon: Icons.home_outlined,
                    color: const Color(0xFF3b82f6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    context: context,
                    theme: theme,
                    title: 'Clientes',
                    value: _formatNumber(stats.myClients),
                    icon: Icons.people_outlined,
                    color: const Color(0xFF10b981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    context: context,
                    theme: theme,
                    title: 'Vistorias',
                    value: _formatNumber(stats.myInspections),
                    icon: Icons.task_alt_outlined,
                    color: const Color(0xFFf59e0b),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    context: context,
                    theme: theme,
                    title: 'Comissões',
                    value: _formatCurrency(stats.myCommissions),
                    icon: Icons.attach_money_outlined,
                    color: const Color(0xFFec4899),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivitiesSection(BuildContext context, ThemeData theme) {
    final stats = _dashboardData?.stats;
    final activityStats = _dashboardData?.activityStats;
    if (stats == null) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Atividades'),
          const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isTablet = screenWidth > 600;
            final spacing = isTablet ? 16.0 : 12.0;
            
            return Row(
              children: [
                Expanded(
                  child: _buildActivityCard(
                    context: context,
                    theme: theme,
                title: 'Tarefas',
                value: _formatNumber(stats.myTasks),
                    icon: Icons.assignment_outlined,
                    color: const Color(0xFF3b82f6),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: _buildActivityCard(
                    context: context,
                    theme: theme,
                title: 'Agendamentos',
                value: _formatNumber(activityStats?.appointmentsThisMonth ?? 0),
                    subtitle: 'Este mês',
                    icon: Icons.calendar_today_outlined,
                    color: const Color(0xFFf59e0b),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: _buildActivityCard(
                    context: context,
                    theme: theme,
                title: 'Matches',
                value: _formatNumber(stats.myMatches),
                    subtitle: 'Pendentes',
                    icon: Icons.favorite_outline,
                    color: const Color(0xFF10b981),
                  ),
                ),
              ],
            );
          },
        ),
        if (activityStats != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: ThemeHelpers.shadowColor(context),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Taxa de Conclusão',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    Text(
                      '${activityStats.completionRate.toStringAsFixed(1)}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: activityStats.completionRate / 100,
                  backgroundColor: AppColors.primary.primary.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.primary.primary,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  minHeight: 10,
                ),
              ],
            ),
          ),
        ],
      ],
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
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmall = screenWidth < 300;
        final padding = isSmall ? 12.0 : 16.0;
        final iconSize = isSmall ? 18.0 : 20.0;
        final iconPadding = isSmall ? 6.0 : 8.0;
        
        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: ThemeHelpers.shadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: iconSize),
                  ),
                ],
              ),
              SizedBox(height: isSmall ? 8 : 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                    fontSize: isSmall ? 18 : null,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontSize: isSmall ? 12 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: isSmall ? 10 : 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPerformanceCard(BuildContext context, ThemeData theme) {
    final performance = _dashboardData?.performance;
    final gamification = _dashboardData?.gamification;
    if (performance == null || gamification == null)
      return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ThemeHelpers.shadowColor(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título e informações principais
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Performance Mensal'),
                    const SizedBox(height: 8),
                    Text(
                      _formatCurrency(performance.thisMonth),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(
                        performance.growthPercentage >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        color: performance.growthPercentage >= 0
                            ? AppColors.status.success
                            : AppColors.status.error,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${performance.growthPercentage.toStringAsFixed(1)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: performance.growthPercentage >= 0
                              ? AppColors.status.success
                              : AppColors.status.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'vs mês anterior',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Ranking e Nível
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranking',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#${performance.ranking} de ${performance.totalUsers}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nível',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nível ${gamification.level}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pontos',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${gamification.currentPoints}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Breakdown de pontos (gráfico simples com barras)
          ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Breakdown de Pontos',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 16),
            _buildPointsBreakdown(gamification.pointsBreakdown, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildPointsBreakdown(
    DashboardPointsBreakdown breakdown,
    ThemeData theme,
  ) {
    final total =
        breakdown.sales +
        breakdown.rentals +
        breakdown.clients +
        breakdown.appointments +
        breakdown.tasks +
        breakdown.other;

    if (total == 0) {
      return Text(
        'Nenhum ponto registrado',
        style: theme.textTheme.bodySmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      );
    }

    return Column(
      children: [
        _buildBreakdownBar(
          label: 'Vendas',
          value: breakdown.sales,
          total: total,
          color: AppColors.status.success,
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildBreakdownBar(
          label: 'Aluguéis',
          value: breakdown.rentals,
          total: total,
          color: Colors.pink,
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildBreakdownBar(
          label: 'Clientes',
          value: breakdown.clients,
          total: total,
          color: AppColors.primary.primary,
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildBreakdownBar(
          label: 'Agendamentos',
          value: breakdown.appointments,
          total: total,
          color: Colors.orange,
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildBreakdownBar(
          label: 'Tarefas',
          value: breakdown.tasks,
          total: total,
          color: Colors.purple,
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildBreakdownBar(
          label: 'Outros',
          value: breakdown.other,
          total: total,
          color: Colors.grey,
          theme: theme,
        ),
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
    final percentage = total > 0 ? (value / total) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 24,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 50,
          child: Text(
            '$value',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingAppointments(BuildContext context, ThemeData theme) {
    final appointments = _dashboardData?.upcomingAppointments ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Próximos Compromissos'),
        const SizedBox(height: 16),
        if (appointments.isNotEmpty)
          ...appointments
              .take(5)
              .map(
                (appointment) => _buildAppointmentCard(
                  context: context,
                  theme: theme,
                  appointment: appointment,
                ),
              )
        else
          _buildEmptyState(
            icon: Icons.calendar_today_outlined,
            title: 'Nenhum agendamento',
            message: 'Você não tem compromissos agendados no momento. Que tal agendar uma visita?',
            actionLabel: null,
            onAction: null,
            isCard: false,
          ),
      ],
    );
  }

  Widget _buildAppointmentCard({
    required BuildContext context,
    required ThemeData theme,
    required DashboardAppointment appointment,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_today,
              color: AppColors.primary.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appointment.client,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${appointment.date} às ${appointment.time}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
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

  Widget _buildRecentActivities(BuildContext context, ThemeData theme) {
    final activities = _dashboardData?.recentActivities ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Atividades Recentes'),
        const SizedBox(height: 16),
        if (activities.isNotEmpty)
          ...activities
              .take(5)
              .map(
                (activity) => _buildActivityItem(
                  context: context,
                  theme: theme,
                  activity: activity,
                ),
              )
        else
          _buildEmptyState(
            icon: Icons.history_outlined,
            title: 'Nenhuma atividade recente',
            message: 'Suas atividades aparecerão aqui conforme você usar o sistema.',
            actionLabel: null,
            onAction: null,
            isCard: false,
          ),
      ],
    );
  }

  Widget _buildActivityItem({
    required BuildContext context,
    required ThemeData theme,
    required DashboardActivity activity,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.primary.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activity.time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyGoalsSection(BuildContext context, ThemeData theme) {
    final goals = _dashboardData?.monthlyGoals;
    final hasGoals = goals != null &&
        (goals.sales != null || goals.commissions != null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ThemeHelpers.shadowColor(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Metas Mensais'),
          const SizedBox(height: 16),
          if (hasGoals) 
            _buildGoalsContent(context, theme, goals)
          else
            _buildEmptyState(
              icon: Icons.track_changes_outlined,
              title: 'Nenhuma meta definida',
              message: 'Configure suas metas mensais para acompanhar seu progresso e alcançar seus objetivos!',
              actionLabel: null,
              onAction: null,
            ),
        ],
      ),
    );
  }

  Widget _buildGoalsContent(
    BuildContext context,
    ThemeData theme,
    DashboardMonthlyGoals goals,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (goals.sales != null)
          _buildGoalProgress(
            context: context,
            theme: theme,
            label: 'Vendas',
            current: goals.sales!.current.toInt(),
            target: goals.sales!.target.toInt(),
            percentage: goals.sales!.percentage,
            icon: Icons.home_work_outlined,
          ),
        if (goals.sales != null && goals.commissions != null)
          const SizedBox(height: 16),
        if (goals.commissions != null)
          _buildGoalProgress(
            context: context,
            theme: theme,
            label: 'Comissões',
            current: goals.commissions!.current.toInt(),
            target: goals.commissions!.target.toInt(),
            percentage: goals.commissions!.percentage,
            icon: Icons.attach_money_outlined,
            isCurrency: true,
          ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isCurrency
                    ? '${_formatCurrency(current.toDouble())} / ${_formatCurrency(target.toDouble())}'
                    : '${_formatNumber(current)} / ${_formatNumber(target)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: AppColors.background.backgroundSecondary,
            valueColor: AlwaysStoppedAnimation<Color>(
              percentage >= 100
                  ? AppColors.status.success
                  : AppColors.primary.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${percentage.toStringAsFixed(1)}% concluído',
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildConversionMetrics(BuildContext context, ThemeData theme) {
    final metrics = _dashboardData?.conversionMetrics;
    if (metrics == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ThemeHelpers.shadowColor(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Métricas de Conversão'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  theme: theme,
                  label: 'Taxa Visitas/Vendas',
                  value: '${metrics.visitsToSales.toStringAsFixed(1)}%',
                  icon: Icons.trending_up_outlined,
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: ThemeHelpers.borderLightColor(context),
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: _buildMetricItem(
                  theme: theme,
                  label: 'Matches Aceitos',
                  value: _formatNumber(metrics.matchesAccepted),
                  icon: Icons.favorite_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary.primary, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
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

  /// Widget padrão para títulos de seções
  Widget _buildSectionTitle(String title, {double? topPadding}) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding ?? 0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
          fontSize: 20,
        ),
      ),
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
    
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 48,
            color: AppColors.primary.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          textAlign: TextAlign.center,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary.primary,
              foregroundColor: ThemeHelpers.onPrimaryColor(context),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );

    if (isCard) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: ThemeHelpers.shadowColor(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: content,
    );
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmall = screenWidth < 350;
        final padding = isSmall ? 12.0 : 16.0;
        final iconSize = isSmall ? 20.0 : 24.0;
        final iconPadding = isSmall ? 8.0 : 12.0;
        
        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: ThemeHelpers.shadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(height: isSmall ? 12 : 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                    fontSize: isSmall ? 20 : null,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontSize: isSmall ? 12 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
