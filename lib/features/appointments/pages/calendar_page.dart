import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../widgets/appointment_card.dart';
import '../widgets/appointment_filters_sheet.dart';
import '../widgets/appointment_helpers.dart';
import '../widgets/view_mode_selector.dart';
import 'appointment_details_page.dart';
import 'create_appointment_page.dart';

/// Tela premium de Agenda — concentra calendário, indicadores, busca/filtros,
/// múltiplas visualizações (Mês / Semana / Agenda) e timeline detalhado do dia.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with TickerProviderStateMixin {
  // Controle do calendário
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _tableFormat = CalendarFormat.month;
  CalendarViewMode _viewMode = CalendarViewMode.month;

  // Busca / filtros locais
  final TextEditingController _searchController = TextEditingController();
  bool _searchOpen = false;
  late final FocusNode _searchFocusNode;
  CalendarFiltersState _filters = const CalendarFiltersState();

  // Cache para markers do calendário (evita rebuild pesado)
  Map<String, List<Appointment>> _eventsByDay = const {};
  List<Appointment> _lastSeenSource = const [];

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<AppointmentController>();
      ctrl.loadAppointments(reset: true);
      ctrl.loadPendingInvites();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Aplica filtros locais (status / tipo / período / minhas) sobre a lista
  /// retornada pelo controller.
  List<Appointment> _applyLocalFilters(List<Appointment> input) {
    var result = input;
    if (_filters.status != null) {
      result = result.where((a) => a.status == _filters.status).toList();
    }
    if (_filters.type != null) {
      result = result.where((a) => a.type == _filters.type).toList();
    }
    if (_filters.startDate != null && _filters.endDate != null) {
      final s = DateTime(_filters.startDate!.year, _filters.startDate!.month,
          _filters.startDate!.day);
      final e = DateTime(_filters.endDate!.year, _filters.endDate!.month,
          _filters.endDate!.day, 23, 59, 59);
      result = result
          .where((a) =>
              !a.startDate.isBefore(s) && !a.startDate.isAfter(e))
          .toList();
    }
    return result;
  }

  Map<String, List<Appointment>> _bucketize(List<Appointment> source) {
    if (identical(source, _lastSeenSource) && _eventsByDay.isNotEmpty) {
      return _eventsByDay;
    }
    final map = <String, List<Appointment>>{};
    for (final a in source) {
      final key = AppointmentVisuals.dayKey(a.startDate);
      map.putIfAbsent(key, () => []).add(a);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.startDate.compareTo(b.startDate));
    }
    _eventsByDay = map;
    _lastSeenSource = source;
    return map;
  }

  List<Appointment> _eventsFor(DateTime day) {
    return _eventsByDay[AppointmentVisuals.dayKey(day)] ?? const [];
  }

  void _openCreate({DateTime? date}) {
    final base = date ?? _selectedDay;
    final now = DateTime.now();
    final start = DateTime(
      base.year,
      base.month,
      base.day,
      base.year == now.year && base.month == now.month && base.day == now.day
          ? math.min(now.hour + 1, 23)
          : 9,
      0,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAppointmentPage(
          initialStartDate: start,
          initialEndDate: start.add(const Duration(hours: 1)),
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      context.read<AppointmentController>().loadAppointments(reset: true);
    });
  }

  void _openDetails(Appointment a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailsPage(appointmentId: a.id),
      ),
    ).then((_) {
      if (!mounted) return;
      context.read<AppointmentController>().loadAppointments(reset: true);
    });
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppointmentFiltersSheet(
        initial: _filters,
        onApply: (f) {
          setState(() => _filters = f);
          context.read<AppointmentController>().setFilters(
                status: f.status?.value,
                type: f.type?.value,
                startDate: f.startDate,
                endDate: f.endDate,
                onlyMyData: f.onlyMyData,
              );
          context
              .read<AppointmentController>()
              .loadAppointments(reset: true);
        },
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (_searchOpen) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _searchFocusNode.requestFocus(),
        );
      } else {
        _searchController.clear();
        context.read<AppointmentController>().setSearchTerm('');
      }
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Agenda',
      currentBottomNavIndex: 2,
      actions: [
        ChromeToolbarIconButton(
          icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searchOpen ? 'Fechar busca' : 'Buscar',
          onPressed: _toggleSearch,
        ),
        Consumer<AppointmentController>(
          builder: (context, _, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              ChromeToolbarIconButton(
                icon: Icons.tune_rounded,
                tooltip: 'Filtros',
                onPressed: _openFilters,
              ),
              if (_filters.hasActiveFilters)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      body: Consumer<AppointmentController>(
        builder: (context, ctrl, _) {
          if (ctrl.loading && ctrl.appointments.isEmpty) {
            return _buildSkeleton(theme);
          }
          if (ctrl.error != null && ctrl.appointments.isEmpty) {
            return _buildErrorState(theme, ctrl);
          }

          final filtered = _applyLocalFilters(ctrl.filteredAppointments);
          _bucketize(filtered);

          return RefreshIndicator(
            color: AppColors.primary.primary,
            onRefresh: () async {
              await ctrl.loadAppointments(reset: true);
              await ctrl.loadPendingInvites();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
                    child: _searchOpen
                        ? _buildSearchBar(ctrl, theme)
                        : const SizedBox.shrink(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildHero(ctrl, theme, filtered),
                ),
                SliverToBoxAdapter(
                  child: _buildStatsRow(ctrl, theme, filtered),
                ),
                SliverToBoxAdapter(
                  child: _buildPendingInvitesPill(ctrl, theme),
                ),
                SliverToBoxAdapter(
                  child: _buildViewModeSection(theme),
                ),
                if (_viewMode == CalendarViewMode.month ||
                    _viewMode == CalendarViewMode.week)
                  SliverToBoxAdapter(child: _buildCalendar(theme))
                else
                  SliverToBoxAdapter(child: _buildAgendaList(filtered, theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(child: _buildSelectedDayHeader(theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(
                    child: _buildSelectedDayList(theme),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------
  Widget _buildSearchBar(AppointmentController ctrl, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: 'Buscar por título, descrição ou local…',
            hintStyle: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.primary.primary,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      ctrl.setSearchTerm('');
                      setState(() {});
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          onChanged: (v) {
            ctrl.setSearchTerm(v);
            setState(() {});
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HERO HEADER (delegated to _PremiumHero — fluid + responsive)
  // ---------------------------------------------------------------------------
  Widget _buildHero(
    AppointmentController ctrl,
    ThemeData theme,
    List<Appointment> filtered,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final todayAppts =
        filtered.where((a) => _isSameDay(a.startDate, today)).toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final upcomingToday =
        todayAppts.where((a) => !a.endDate.isBefore(now)).toList();
    final next = upcomingToday.isNotEmpty
        ? upcomingToday.first
        : filtered.where((a) => a.startDate.isAfter(now)).fold<Appointment?>(
              null,
              (acc, a) =>
                  acc == null || a.startDate.isBefore(acc.startDate) ? a : acc,
            );

    final tomorrowCount =
        filtered.where((a) => _isSameDay(a.startDate, tomorrow)).length;

    return _PremiumHero(
      next: next,
      todayCount: todayAppts.length,
      tomorrowCount: tomorrowCount,
      onTapNext: () {
        if (next != null) _openDetails(next);
      },
      onTapEmpty: () => _openCreate(),
    );
  }

  // ---------------------------------------------------------------------------
  // STATS ROW
  // ---------------------------------------------------------------------------
  Widget _buildStatsRow(
    AppointmentController ctrl,
    ThemeData theme,
    List<Appointment> filtered,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));

    final todayCount =
        filtered.where((a) => _isSameDay(a.startDate, today)).length;
    final weekCount = filtered
        .where((a) =>
            !a.startDate.isBefore(today) && a.startDate.isBefore(weekEnd))
        .length;
    final pendingCount = filtered
        .where((a) =>
            a.status == AppointmentStatus.scheduled ||
            a.status == AppointmentStatus.confirmed)
        .length;
    final completedCount = filtered
        .where((a) => a.status == AppointmentStatus.completed)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          children: [
            _statCard(
              theme,
              icon: Icons.today_rounded,
              color: AppColors.primary.primary,
              label: 'Hoje',
              value: todayCount.toString(),
              onTap: () => setState(() {
                _selectedDay = today;
                _focusedDay = today;
              }),
            ),
            const SizedBox(width: 10),
            _statCard(
              theme,
              icon: Icons.calendar_view_week_rounded,
              color: AppColors.status.info,
              label: '7 dias',
              value: weekCount.toString(),
            ),
            const SizedBox(width: 10),
            _statCard(
              theme,
              icon: Icons.schedule_rounded,
              color: AppColors.status.warning,
              label: 'Pendentes',
              value: pendingCount.toString(),
            ),
            const SizedBox(width: 10),
            _statCard(
              theme,
              icon: Icons.task_alt_rounded,
              color: AppColors.status.success,
              label: 'Concluídos',
              value: completedCount.toString(),
            ),
            const SizedBox(width: 10),
            _statCard(
              theme,
              icon: Icons.event_available_rounded,
              color: AppColors.status.purple,
              label: 'Total',
              value: filtered.length.toString(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 124,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
          border: Border.all(
            color: isDark
                ? color.withOpacity(0.18)
                : ThemeHelpers.borderColor(context),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: color.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 14),
                ),
                const Spacer(),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PENDING INVITES PILL
  // ---------------------------------------------------------------------------
  Widget _buildPendingInvitesPill(
    AppointmentController ctrl,
    ThemeData theme,
  ) {
    final pending = ctrl.pendingInvites.length;
    if (pending == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.status.warning.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppColors.status.warning.withOpacity(0.32)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.status.warning.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.mark_email_unread_rounded,
                color: AppColors.status.warning,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: '$pending ',
                      style: TextStyle(
                        color: AppColors.status.warning,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: 'convite${pending > 1 ? 's' : ''} aguardando sua resposta',
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE SECTION
  // ---------------------------------------------------------------------------
  Widget _buildViewModeSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: ViewModeSelector(
              value: _viewMode,
              onChanged: (m) {
                setState(() {
                  _viewMode = m;
                  if (m == CalendarViewMode.month) {
                    _tableFormat = CalendarFormat.month;
                  } else if (m == CalendarViewMode.week) {
                    _tableFormat = CalendarFormat.week;
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          _todayButton(theme),
        ],
      ),
    );
  }

  Widget _todayButton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final today = DateTime.now();
    final isOnToday = _isSameDay(_selectedDay, today);
    return InkWell(
      onTap: isOnToday
          ? null
          : () => setState(() {
                _selectedDay = today;
                _focusedDay = today;
              }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isOnToday
              ? AppColors.primary.primary.withOpacity(0.10)
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.white),
          border: Border.all(
            color: isOnToday
                ? AppColors.primary.primary.withOpacity(0.40)
                : ThemeHelpers.borderColor(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.gps_fixed_rounded,
              size: 14,
              color: isOnToday
                  ? AppColors.primary.primary
                  : ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Hoje',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isOnToday
                    ? AppColors.primary.primary
                    : ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CALENDAR (MES / SEMANA)
  // ---------------------------------------------------------------------------
  Widget _buildCalendar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
          border: Border.all(color: ThemeHelpers.borderColor(context)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: TableCalendar<Appointment>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2032, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),
          calendarFormat: _tableFormat,
          startingDayOfWeek: StartingDayOfWeek.monday,
          locale: 'pt_BR',
          rowHeight: 52,
          daysOfWeekHeight: 32,
          availableCalendarFormats: const {
            CalendarFormat.month: 'Mês',
            CalendarFormat.week: 'Semana',
          },
          eventLoader: _eventsFor,
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextFormatter: (date, locale) {
              final f = DateFormat('MMMM yyyy', 'pt_BR').format(date);
              return AppointmentVisuals.capitalize(f);
            },
            titleTextStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ) ??
                const TextStyle(),
            leftChevronIcon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                color: primary,
                size: 22,
              ),
            ),
            rightChevronIcon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: primary,
                size: 22,
              ),
            ),
            headerPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
            weekendStyle: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
            dowTextFormatter: (date, locale) {
              final raw = DateFormat.E(locale).format(date);
              return raw.length >= 3
                  ? raw.substring(0, 3).toUpperCase()
                  : raw.toUpperCase();
            },
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            cellMargin: const EdgeInsets.all(3),
            defaultTextStyle: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
            weekendTextStyle: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          calendarBuilders: CalendarBuilders<Appointment>(
            defaultBuilder: (context, day, focused) =>
                _dayCell(day, false, false, false),
            todayBuilder: (context, day, focused) =>
                _dayCell(day, false, true, false),
            selectedBuilder: (context, day, focused) =>
                _dayCell(day, true, _isSameDay(day, DateTime.now()), false),
            outsideBuilder: (context, day, focused) =>
                _dayCell(day, false, false, true),
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(4).map((e) {
                    final c = AppointmentVisuals.colorFromHex(e.color);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.2),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.withOpacity(0.5),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
          onPageChanged: (focused) {
            _focusedDay = focused;
          },
          onFormatChanged: (format) {
            setState(() {
              _tableFormat = format;
              _viewMode = format == CalendarFormat.week
                  ? CalendarViewMode.week
                  : CalendarViewMode.month;
            });
          },
        ),
      ),
    );
  }

  Widget _dayCell(
    DateTime day,
    bool selected,
    bool isToday,
    bool outside,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;
    final hasEvents = _eventsFor(day).isNotEmpty;
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color textColor;
    if (selected) {
      textColor = Colors.white;
    } else if (outside) {
      textColor = ThemeHelpers.textSecondaryColor(context).withOpacity(0.4);
    } else if (isToday) {
      textColor = primary;
    } else if (isWeekend) {
      textColor = ThemeHelpers.textSecondaryColor(context);
    } else {
      textColor = ThemeHelpers.textColor(context);
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [primary, primary.withOpacity(0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: !selected && isToday
            ? primary.withOpacity(isDark ? 0.18 : 0.10)
            : null,
        borderRadius: BorderRadius.circular(12),
        border: !selected && isToday
            ? Border.all(color: primary.withOpacity(0.5), width: 1.2)
            : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primary.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: selected || isToday ? FontWeight.w800 : FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
          if (selected && hasEvents)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTED DAY HEADER
  // ---------------------------------------------------------------------------
  Widget _buildSelectedDayHeader(ThemeData theme) {
    final events = _eventsFor(_selectedDay);
    final isToday = _isSameDay(_selectedDay, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? 'Hoje'
                      : AppointmentVisuals.formattedFullDate(_selectedDay),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (!isToday)
                  Text(
                    DateFormat('dd/MM/yyyy').format(_selectedDay),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (events.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${events.length} ${events.length == 1 ? 'item' : 'itens'}',
                style: TextStyle(
                  color: AppColors.primary.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => _openCreate(date: _selectedDay),
            icon: const Icon(Icons.add_rounded, size: 20),
            tooltip: 'Novo agendamento neste dia',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTED DAY LIST (Timeline)
  // ---------------------------------------------------------------------------
  Widget _buildSelectedDayList(ThemeData theme) {
    final events = _eventsFor(_selectedDay);
    if (events.isEmpty) {
      return _buildDayEmptyState(theme);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int i = 0; i < events.length; i++) ...[
            _TimelineRow(
              appointment: events[i],
              isLast: i == events.length - 1,
              onTap: () => _openDetails(events[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.primary.withOpacity(0.08),
                border: Border.all(
                  color: AppColors.primary.primary.withOpacity(0.20),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.event_available_rounded,
                size: 32,
                color: AppColors.primary.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Dia livre',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nenhum agendamento em ${DateFormat('dd/MM/yyyy').format(_selectedDay)}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Criar agendamento',
              icon: Icons.add_rounded,
              onPressed: () => _openCreate(date: _selectedDay),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AGENDA (LISTA POR DIA)
  // ---------------------------------------------------------------------------
  Widget _buildAgendaList(List<Appointment> filtered, ThemeData theme) {
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.event_busy_rounded,
                size: 48,
                color: ThemeHelpers.textSecondaryColor(context).withOpacity(0.6),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhum agendamento encontrado',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _filters.hasActiveFilters
                    ? 'Tente ajustar ou remover os filtros aplicados'
                    : 'Crie um novo agendamento para começar',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 18),
              if (_filters.hasActiveFilters)
                CustomButton(
                  text: 'Limpar filtros',
                  variant: ButtonVariant.secondary,
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    setState(() => _filters = const CalendarFiltersState());
                    final ctrl = context.read<AppointmentController>();
                    ctrl.clearFilters();
                    ctrl.loadAppointments(reset: true);
                  },
                )
              else
                CustomButton(
                  text: 'Novo agendamento',
                  icon: Icons.add_rounded,
                  onPressed: () => _openCreate(),
                ),
            ],
          ),
        ),
      );
    }

    // Agrupar por dia
    final groups = <DateTime, List<Appointment>>{};
    for (final a in filtered) {
      final k = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      groups.putIfAbsent(k, () => []).add(a);
    }
    final sortedKeys = groups.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          for (final day in sortedKeys) ...[
            _agendaDayHeader(theme, day, groups[day]!.length),
            const SizedBox(height: 8),
            for (int i = 0; i < groups[day]!.length; i++) ...[
              AppointmentCard(
                appointment: groups[day]![i],
                dense: true,
                onTap: () => _openDetails(groups[day]![i]),
              ),
              if (i != groups[day]!.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _agendaDayHeader(ThemeData theme, DateTime day, int count) {
    final isToday = _isSameDay(day, DateTime.now());
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isTomorrow = _isSameDay(day, tomorrow);
    final isPast = day.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

    final accent = isToday
        ? AppColors.primary.primary
        : isPast
            ? ThemeHelpers.textSecondaryColor(context)
            : AppColors.status.info;

    final label = isToday
        ? 'HOJE'
        : isTomorrow
            ? 'AMANHÃ'
            : DateFormat('EEEE', 'pt_BR').format(day).toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                Text(
                  '${day.day}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  AppointmentVisuals.capitalize(
                    DateFormat('MMM', 'pt_BR').format(day),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${count} agendamento${count > 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR / SKELETON
  // ---------------------------------------------------------------------------
  Widget _buildErrorState(ThemeData theme, AppointmentController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.status.error.withOpacity(0.10),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Não conseguimos carregar a agenda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              ctrl.error ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            CustomButton(
              text: 'Tentar novamente',
              icon: Icons.refresh_rounded,
              onPressed: () => ctrl.loadAppointments(reset: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 110, borderRadius: 22),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(
                4,
                (_) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SkeletonBox(width: 124, borderRadius: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SkeletonBox(height: 50, borderRadius: 14),
          const SizedBox(height: 14),
          SkeletonBox(height: 320, borderRadius: 22),
          const SizedBox(height: 18),
          SkeletonBox(height: 24, width: 160, borderRadius: 8),
          const SizedBox(height: 12),
          for (int i = 0; i < 3; i++) ...[
            SkeletonBox(height: 96, borderRadius: 18),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ===========================================================================
// PREMIUM HERO — fluid background + responsive layout + entrance animation
// ===========================================================================

/// Cabeçalho premium da Agenda. Apresenta saudação, contexto do dia e o
/// próximo compromisso de forma orgânica: fundo com orbs em movimento lento,
/// camada de vidro translúcido e tipografia hierárquica que se adapta ao
/// espaço disponível (FittedBox, LayoutBuilder).
class _PremiumHero extends StatefulWidget {
  final Appointment? next;
  final int todayCount;
  final int tomorrowCount;
  final VoidCallback onTapNext;
  final VoidCallback onTapEmpty;

  const _PremiumHero({
    required this.next,
    required this.todayCount,
    required this.tomorrowCount,
    required this.onTapNext,
    required this.onTapEmpty,
  });

  @override
  State<_PremiumHero> createState() => _PremiumHeroState();
}

class _PremiumHeroState extends State<_PremiumHero>
    with TickerProviderStateMixin {
  late final AnimationController _bg;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _bg = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _bg.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;
    final accent = widget.next != null
        ? AppointmentVisuals.colorFromHex(widget.next!.color)
        : primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_bg, _enter]),
        builder: (context, _) {
          final t = _bg.value;
          final e = Curves.easeOutCubic.transform(_enter.value);

          return Transform.translate(
            offset: Offset(0, 18 * (1 - e)),
            child: Opacity(
              opacity: e,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF13131F)
                        : Colors.white,
                    border: Border.all(
                      color: accent.withOpacity(isDark ? 0.22 : 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(isDark ? 0.18 : 0.10),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Orbs animados como background fluido
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _HeroFluidPainter(
                              t: t,
                              accent: accent,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                      // Gradiente de "fade" que apoia legibilidade
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.02),
                                        Colors.transparent,
                                      ]
                                    : [
                                        Colors.white.withOpacity(0.55),
                                        Colors.white.withOpacity(0.10),
                                      ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Conteúdo
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: _Content(
                          next: widget.next,
                          todayCount: widget.todayCount,
                          tomorrowCount: widget.tomorrowCount,
                          accent: accent,
                          isDark: isDark,
                          onTapNext: widget.onTapNext,
                          onTapEmpty: widget.onTapEmpty,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final Appointment? next;
  final int todayCount;
  final int tomorrowCount;
  final Color accent;
  final bool isDark;
  final VoidCallback onTapNext;
  final VoidCallback onTapEmpty;

  const _Content({
    required this.next,
    required this.todayCount,
    required this.tomorrowCount,
    required this.accent,
    required this.isDark,
    required this.onTapNext,
    required this.onTapEmpty,
  });

  IconData _greetingIcon(int hour) {
    if (hour < 6) return Icons.bedtime_rounded;
    if (hour < 12) return Icons.wb_sunny_rounded;
    if (hour < 18) return Icons.light_mode_rounded;
    return Icons.nights_stay_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GreetingRow(
          greetingIcon: _greetingIcon(now.hour),
          todayCount: todayCount,
          now: now,
        ),
        const SizedBox(height: 16),
        if (next == null)
          _EmptyStateSurface(
            todayCount: todayCount,
            tomorrowCount: tomorrowCount,
            onTap: onTapEmpty,
          )
        else
          _NextSurface(
            next: next!,
            accent: accent,
            isDark: isDark,
            onTap: onTapNext,
          ),
      ],
    );
  }
}

/// Linha superior — saudação + contador do dia. Fully responsive.
class _GreetingRow extends StatelessWidget {
  final IconData greetingIcon;
  final int todayCount;
  final DateTime now;
  const _GreetingRow({
    required this.greetingIcon,
    required this.todayCount,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = todayCount > 0
        ? AppColors.primary.primary
        : AppColors.status.success;

    return LayoutBuilder(builder: (context, c) {
      final tight = c.maxWidth < 320;
      final greetingText = '${AppointmentVisuals.greeting()}, corretor';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.primary.withOpacity(0.20),
                  ),
                ),
                child: Icon(
                  greetingIcon,
                  size: 13,
                  color: AppColors.primary.primary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  greetingText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (!tight) ...[
                const SizedBox(width: 10),
                _DayPulse(
                  count: todayCount,
                  color: color,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Data grande responsiva — encolhe sem quebrar
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AppointmentVisuals.formattedFullDate(now),
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                height: 1.05,
                letterSpacing: -0.7,
              ),
            ),
          ),
          if (tight) ...[
            const SizedBox(height: 8),
            _DayPulse(count: todayCount, color: color),
          ],
        ],
      );
    });
  }
}

/// Pílula viva ("3 hoje" / "Dia livre") com glow.
class _DayPulse extends StatelessWidget {
  final int count;
  final Color color;
  const _DayPulse({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            count > 0 ? '$count hoje' : 'Dia livre',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Superfície fluida do "próximo compromisso" — vidro translúcido sobre os
/// orbs, com pillar de horário, título e localização opcional.
class _NextSurface extends StatelessWidget {
  final Appointment next;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _NextSurface({
    required this.next,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isHappening =
        now.isAfter(next.startDate) && now.isBefore(next.endDate);
    final relative =
        AppointmentVisuals.relativeTimeLabel(next.startDate, next.endDate);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.white.withOpacity(0.65),
            border: Border.all(color: accent.withOpacity(0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tag superior + relative
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isHappening
                              ? Icons.bolt_rounded
                              : Icons.schedule_rounded,
                          size: 11,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isHappening ? 'AO VIVO' : 'PRÓXIMO',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      relative,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, c) {
                final pillar = _TimePillar(
                  start: next.startDate,
                  end: next.endDate,
                  accent: accent,
                );
                final body = _NextBody(next: next, accent: accent);

                if (c.maxWidth < 260) {
                  // Empilhado quando muito apertado
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [pillar]),
                      const SizedBox(height: 10),
                      body,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    pillar,
                    const SizedBox(width: 14),
                    Expanded(child: body),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        color: accent, size: 22),
                  ],
                );
              }),
              if (next.location != null && next.location!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withOpacity(0.14)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 13,
                          color:
                              ThemeHelpers.textSecondaryColor(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          next.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NextBody extends StatelessWidget {
  final Appointment next;
  final Color accent;
  const _NextBody({required this.next, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              AppointmentVisuals.iconFor(next.type),
              color: accent,
              size: 13,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                next.type.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          next.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1.2,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

/// Pillar do horário (início → término) — foco visual do hero.
class _TimePillar extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final Color accent;
  const _TimePillar({
    required this.start,
    required this.end,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withOpacity(0.20),
            accent.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              AppointmentVisuals.formattedTime(start),
              style: theme.textTheme.titleLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 22,
            height: 1.5,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              AppointmentVisuals.formattedTime(end),
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent.withOpacity(0.85),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio fluido — quando o corretor não tem nada agendado.
class _EmptyStateSurface extends StatelessWidget {
  final int todayCount;
  final int tomorrowCount;
  final VoidCallback onTap;

  const _EmptyStateSurface({
    required this.todayCount,
    required this.tomorrowCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasToday = todayCount > 0;
    final color = AppColors.status.success;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withOpacity(0.06),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasToday
                      ? Icons.celebration_rounded
                      : Icons.beach_access_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasToday
                          ? 'Você concluiu o dia'
                          : 'Nenhum compromisso à vista',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tomorrowCount > 0
                          ? 'Amanhã: $tomorrowCount agendamento${tomorrowCount > 1 ? 's' : ''}'
                          : 'Toque para criar um novo agendamento',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, color: color, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter dos orbs vermelhos blurrados que orbitam lentamente — gera a
/// sensação de fluido orgânico no fundo do hero.
class _HeroFluidPainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool isDark;

  _HeroFluidPainter({
    required this.t,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final twoPi = 2 * math.pi;

    final orbs = <_Orb>[
      _Orb(
        cx: w * (0.18 + 0.05 * math.sin(t * twoPi)),
        cy: h * (0.28 + 0.10 * math.cos(t * twoPi)),
        r: w * 0.36,
        opacity: isDark ? 0.22 : 0.10,
      ),
      _Orb(
        cx: w * (0.86 + 0.06 * math.cos(t * twoPi + math.pi / 3)),
        cy: h * (0.22 + 0.08 * math.sin(t * twoPi + math.pi / 4)),
        r: w * 0.30,
        opacity: isDark ? 0.18 : 0.08,
      ),
      _Orb(
        cx: w * (0.55 + 0.04 * math.sin(t * twoPi + math.pi / 2)),
        cy: h * (0.92 + 0.06 * math.cos(t * twoPi + math.pi)),
        r: w * 0.42,
        opacity: isDark ? 0.14 : 0.07,
      ),
    ];

    for (final orb in orbs) {
      final paint = Paint()
        ..color = accent.withOpacity(orb.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
      canvas.drawCircle(Offset(orb.cx, orb.cy), orb.r, paint);
    }

    // Linha sutil de "highlight" diagonal — toque editorial
    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(isDark ? 0.04 : 0.10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.5));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.5), highlight);
  }

  @override
  bool shouldRepaint(covariant _HeroFluidPainter old) =>
      old.t != t || old.accent != accent || old.isDark != isDark;
}

class _Orb {
  final double cx;
  final double cy;
  final double r;
  final double opacity;
  _Orb({
    required this.cx,
    required this.cy,
    required this.r,
    required this.opacity,
  });
}

/// Linha de timeline para um agendamento dentro do dia selecionado.
class _TimelineRow extends StatelessWidget {
  final Appointment appointment;
  final bool isLast;
  final VoidCallback onTap;

  const _TimelineRow({
    required this.appointment,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppointmentVisuals.colorFromHex(appointment.color);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Faixa lateral com bullet
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.55),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                      border: Border.all(
                        color: ThemeHelpers.cardBackgroundColor(context),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: AppointmentCard(
                appointment: appointment,
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
