import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/rental_models.dart';
import '../services/rental_service.dart';
import '../widgets/rental_property_picker.dart';
import '../widgets/rental_status_ui.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);
final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// **Dashboard de Locações** (`/rentals/dashboard`) — paridade com
/// `RentalDashboardPage.tsx`: KPIs da carteira, pagamentos do mês, gráfico de
/// receita (pago × pendente), pagamentos por status e locações recentes.
/// Filtros: período do gráfico (6/12 meses), status e imóvel.
class RentalDashboardPage extends StatefulWidget {
  const RentalDashboardPage({super.key});

  @override
  State<RentalDashboardPage> createState() => _RentalDashboardPageState();
}

class _RentalDashboardPageState extends State<RentalDashboardPage> {
  static const double _kPagePadH = 16;

  RentalDashboardData? _data;
  bool _loading = true;
  String? _error;

  int _periodMonths = 12;
  RentalStatus? _status;
  String? _propertyId;
  String? _propertyLabel;

  ModuleAccessService get _access => ModuleAccessService.instance;
  bool get _canView => _access.hasPermission(RentalPermissions.viewDashboard);
  bool get _canViewFinancials =>
      _access.hasPermission(RentalPermissions.viewFinancials);
  bool get _canCreate => _access.hasPermission(RentalPermissions.create);

  @override
  void initState() {
    super.initState();
    if (_canView) _load();
  }

  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RentalService.instance.getDashboard(
      periodMonths: _periodMonths,
      status: _status,
      propertyId: _propertyId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar dashboard de locações';
      }
    });
  }

  void _setPeriod(int months) {
    if (_periodMonths == months) return;
    setState(() => _periodMonths = months);
    _load();
  }

  void _setStatus(RentalStatus? status) {
    if (_status == status) return;
    setState(() => _status = status);
    _load();
  }

  Future<void> _pickProperty() async {
    final property = await showRentalPropertyPicker(context);
    if (!mounted) return;
    if (property == null) return;
    setState(() {
      _propertyId = property.id;
      _propertyLabel = property.title;
    });
    _load();
  }

  void _clearProperty() {
    if (_propertyId == null) return;
    setState(() {
      _propertyId = null;
      _propertyLabel = null;
    });
    _load();
  }

  void _openRental(String id) {
    Navigator.of(context).pushNamed('/rentals/$id').then((_) => _load());
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Dashboard de Locações',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Dashboard de Locações',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Ver locações',
          onPressed: () => Navigator.of(context)
              .pushNamed('/rentals')
              .then((_) => _load()),
          icon: Icon(
            LucideIcons.list,
            size: 20,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ],
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _load,
        child: _loading && _data == null
            ? _buildSkeleton(context)
            : _error != null && _data == null
                ? _buildError(context)
                : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = _data ?? RentalDashboardData.zero;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPagePadH, 10, _kPagePadH, 0),
                child: _buildHero(context, data),
              ),
              const SizedBox(height: 14),
              _buildFilterRail(context),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPagePadH, 16, _kPagePadH, 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading)
                      const LinearProgressIndicator(minHeight: 2)
                          .animate()
                          .fadeIn(duration: 150.ms),
                    if (data.overduePayments > 0 || data.expiringContracts > 0)
                      _buildAlerts(context, data),
                    if (_canViewFinancials) ...[
                      _buildMonthPayments(context, data),
                      _buildRevenueChart(context, data),
                    ],
                    _buildPaymentsByStatus(context, data),
                    _buildRecentRentals(context, data),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Hero: manchete financeira ───────────────────────────────────────────
  //
  // DNA do painel de performance do dashboard geral: a receita mensal da
  // carteira como manchete, medidor de ocupação e leituras operacionais em
  // linha — irmão (não gêmeo) do painel da lista de locações.

  Widget _buildHero(BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final hasAlert = data.overduePayments > 0 || data.expiringContracts > 0;
    final subtitle = hasAlert
        ? [
            if (data.overduePayments > 0)
              '${data.overduePayments} pagamento${data.overduePayments == 1 ? '' : 's'} atrasado${data.overduePayments == 1 ? '' : 's'}',
            if (data.expiringContracts > 0)
              '${data.expiringContracts} contrato${data.expiringContracts == 1 ? '' : 's'} vencendo em 30 dias',
          ].join(' · ')
        : 'Carteira em dia — nenhum alerta no momento.';

    final occupancy = (data.occupancyRate / 100).clamp(0.0, 1.0);
    final occupancyLabel =
        '${data.occupancyRate.toStringAsFixed(data.occupancyRate % 1 == 0 ? 0 : 1).replaceAll('.', ',')}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DASHBOARD · LOCAÇÕES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_canViewFinancials) ...[
                    Text(
                      'RECEITA MENSAL DA CARTEIRA',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _money.format(data.totalMonthlyRevenue),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          height: 1.0,
                          letterSpacing: -1.2,
                          fontSize: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'média de ${_compact.format(data.averageRentalValue)} por contrato',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'CARTEIRA SOB GESTÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${data.activeRentals} contrato${data.activeRentals == 1 ? '' : 's'} ativo${data.activeRentals == 1 ? '' : 's'}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.7,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_canCreate) ...[
              const SizedBox(width: 10),
              InkWell(
                onTap: () => Navigator.of(context)
                    .pushNamed('/rentals/create')
                    .then((_) => _load()),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 14, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        'Nova',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'OCUPAÇÃO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                fontSize: 9.5,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 6,
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.4),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          width: c.maxWidth * occupancy,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              colors: [
                                emerald.withValues(alpha: 0.7),
                                emerald,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              occupancyLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: emerald,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _heroReading(context, emerald, '${data.activeRentals} ativas'),
            _heroReading(context, blue, '${data.pendingRentals} pendentes'),
            _heroReading(
              context,
              amber,
              '${data.expiringContracts} vencendo em 30d',
            ),
            _heroReading(
              context,
              danger,
              '${data.overduePayments} atrasado${data.overduePayments == 1 ? '' : 's'}',
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: data.overduePayments > 0
                ? danger
                : hasAlert
                    ? amber
                    : secondary,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _heroReading(BuildContext context, Color tone, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context).withValues(alpha: 0.85),
            height: 1.0,
          ),
        ),
      ],
    );
  }

  // ─── Filtros (rail de chips) ─────────────────────────────────────────────

  Widget _buildFilterRail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(_kPagePadH, 0, _kPagePadH, 10),
        child: Row(
          children: [
            _FilterChip(
              label: '6 meses',
              tone: blue,
              selected: _periodMonths == 6,
              onTap: () => _setPeriod(6),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: '12 meses',
              tone: blue,
              selected: _periodMonths == 12,
              onTap: () => _setPeriod(12),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 22,
              color: ThemeHelpers.borderLightColor(context),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Todos',
              tone: accent,
              selected: _status == null,
              onTap: () => _setStatus(null),
            ),
            for (final s in const [
              RentalStatus.active,
              RentalStatus.pending,
              RentalStatus.expired,
              RentalStatus.cancelled,
            ]) ...[
              const SizedBox(width: 8),
              _FilterChip(
                label: s.label,
                tone: rentalStatusColor(context, s),
                selected: _status == s,
                onTap: () => _setStatus(s),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 22,
              color: ThemeHelpers.borderLightColor(context),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _propertyLabel == null
                  ? 'Imóvel'
                  : (_propertyLabel!.length > 22
                      ? '${_propertyLabel!.substring(0, 22)}…'
                      : _propertyLabel!),
              icon: LucideIcons.house,
              tone: accent,
              selected: _propertyId != null,
              onTap: _pickProperty,
              onClear: _propertyId != null ? _clearProperty : null,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Alertas ─────────────────────────────────────────────────────────────

  Widget _buildAlerts(BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    Widget alert(IconData icon, Color tone, String text) {
      return InkWell(
        onTap: () => Navigator.of(context)
            .pushNamed('/rentals')
            .then((_) => _load()),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 15, color: tone),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.overduePayments > 0)
            alert(
              LucideIcons.triangleAlert,
              danger,
              '${data.overduePayments} pagamento${data.overduePayments == 1 ? '' : 's'} '
              'atrasado${data.overduePayments == 1 ? '' : 's'} — toque para ver as locações.',
            ),
          if (data.expiringContracts > 0)
            alert(
              LucideIcons.calendarClock,
              amber,
              '${data.expiringContracts} contrato${data.expiringContracts == 1 ? '' : 's'} '
              'vencendo nos próximos 30 dias.',
            ),
        ],
      ),
    );
  }

  // ─── Painéis ─────────────────────────────────────────────────────────────

  Widget _panelHeader(
    BuildContext context, {
    required Color tone,
    required IconData icon,
    required String eyebrow,
    required String title,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            child: Icon(icon, color: tone, size: 20),
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
                        color: tone,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tone.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      eyebrow,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
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

  Widget _buildMonthPayments(BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    Widget block(IconData icon, Color tone, String label, double value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tone.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(height: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: tone,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _compact.format(value),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          context,
          tone: emerald,
          icon: LucideIcons.calendarCheck,
          eyebrow: 'MÊS ATUAL',
          title: 'Pagamentos do mês',
          hint: 'Quanto já entrou e quanto ainda está pendente neste mês.',
        ),
        Row(
          children: [
            block(LucideIcons.circleCheckBig, emerald, 'Recebido',
                data.paidThisMonth),
            const SizedBox(width: 10),
            block(LucideIcons.clock3, amber, 'Pendente',
                data.pendingThisMonth),
            const SizedBox(width: 10),
            block(LucideIcons.banknote, blue, 'Esperado',
                data.paidThisMonth + data.pendingThisMonth),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildRevenueChart(BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final points = data.monthlyRevenueChart;

    Widget legendItem(Color tone, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          context,
          tone: amber,
          icon: LucideIcons.chartColumn,
          eyebrow: 'RECEITA',
          title: 'Últimos $_periodMonths meses',
          hint: 'Pago × pendente por mês de referência.',
        ),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Sem dados de receita no período.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 168,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: _RevenueBars(
                points: points,
                paidColor: emerald,
                pendingColor: amber,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              legendItem(emerald, 'Pago'),
              const SizedBox(width: 14),
              legendItem(amber, 'Pendente'),
            ],
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPaymentsByStatus(
      BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final items = data.paymentsByStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          context,
          tone: blue,
          icon: LucideIcons.chartPie,
          eyebrow: 'COBRANÇAS',
          title: 'Pagamentos por status',
          hint: 'Distribuição das parcelas da carteira por situação.',
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Nenhuma parcela registrada ainda.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          )
        else
          for (final item in items) _buildStatusRow(context, item),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildStatusRow(BuildContext context, RentalPaymentsByStatus item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = rentalPaymentStatusColor(context, item.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child: Icon(rentalPaymentStatusIcon(item.status),
                color: tone, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.status.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.count} pagamento${item.count == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _canViewFinancials ? _money.format(item.totalValue) : '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRentals(BuildContext context, RentalDashboardData data) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final items = data.recentRentals;
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          context,
          tone: accent,
          icon: LucideIcons.keyRound,
          eyebrow: 'RECENTES',
          title: 'Últimas locações',
          hint: 'Os contratos mais recentes da carteira — toque para abrir.',
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Nenhuma locação registrada ainda.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          )
        else
          for (final rental in items)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openRental(rental.id),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: ThemeHelpers.borderLightColor(context)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rental.tenantName.trim().isEmpty
                                  ? 'Inquilino não especificado'
                                  : rental.tenantName.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: ThemeHelpers.textColor(context),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (rental.propertyAddress.trim().isNotEmpty)
                                  rental.propertyAddress.trim(),
                                if (rental.startDate != null)
                                  'início ${fmt.format(rental.startDate!.toLocal())}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RentalStatusPill(
                              label: rental.status.label,
                              color:
                                  rentalStatusColor(context, rental.status),
                              icon: rentalStatusIcon(rental.status),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _canViewFinancials
                                ? _money.format(rental.monthlyValue)
                                : '—',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '/mês',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 14, _kPagePadH, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Espelha o hero de manchete financeira: eyebrow, rótulo, valor
          // grande, linha de média, medidor de ocupação e leituras.
          const SkeletonText(width: 150, height: 10),
          const SizedBox(height: 12),
          const SkeletonText(width: 176, height: 9),
          const SizedBox(height: 8),
          const SkeletonText(width: 210, height: 30),
          const SizedBox(height: 7),
          const SkeletonText(width: 190, height: 11),
          const SizedBox(height: 16),
          Row(
            children: const [
              SkeletonText(width: 62, height: 9),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 6, borderRadius: 99)),
              SizedBox(width: 10),
              SkeletonText(width: 34, height: 11),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                const SkeletonText(width: 62, height: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonText(width: 220, height: 12),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                const SkeletonText(width: 74, height: 30, borderRadius: 999),
              ],
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 86, borderRadius: 14),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SkeletonBox(width: double.infinity, height: 168, borderRadius: 14),
          const SizedBox(height: 22),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  SkeletonBox(width: 36, height: 36, borderRadius: 11),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 100, height: 13),
                        SizedBox(height: 7),
                        SkeletonText(width: 150, height: 11),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const SkeletonText(width: 70, height: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _error ?? 'Erro ao carregar dashboard',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }
}

// ─── Gráfico de barras (pago × pendente) ─────────────────────────────────────

class _RevenueBars extends StatelessWidget {
  final List<RentalMonthlyRevenuePoint> points;
  final Color paidColor;
  final Color pendingColor;

  const _RevenueBars({
    required this.points,
    required this.paidColor,
    required this.pendingColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const chartHeight = 128.0;
    var maxValue = 1.0;
    for (final p in points) {
      if (p.revenue > maxValue) maxValue = p.revenue;
      if (p.paid > maxValue) maxValue = p.paid;
      if (p.pending > maxValue) maxValue = p.pending;
    }

    Widget bar(double value, Color tone) {
      final h = (value / maxValue * chartHeight).clamp(2.0, chartHeight);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        width: 9,
        height: h,
        decoration: BoxDecoration(
          color: value <= 0 ? tone.withValues(alpha: 0.18) : tone,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message:
                      '${p.month}\nPago: ${_money.format(p.paid)}\nPendente: ${_money.format(p.pending)}',
                  textAlign: TextAlign.left,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      bar(p.paid, paidColor),
                      const SizedBox(width: 3),
                      bar(p.pending, pendingColor),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p.month,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Chip de filtro ──────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? tone
        : ThemeHelpers.textColor(context).withValues(alpha: 0.75);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? tone.withValues(alpha: isDark ? 0.18 : 0.1)
              : fieldFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tone : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12.5,
                letterSpacing: -0.1,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 5),
              GestureDetector(
                onTap: onClear,
                child: Icon(LucideIcons.x, size: 13, color: fg),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();
  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso ao dashboard de locações.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de ver o dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
