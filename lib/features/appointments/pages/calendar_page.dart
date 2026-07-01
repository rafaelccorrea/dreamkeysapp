import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/navigation/adaptive_page_route.dart';
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
      final s = DateTime(
        _filters.startDate!.year,
        _filters.startDate!.month,
        _filters.startDate!.day,
      );
      final e = DateTime(
        _filters.endDate!.year,
        _filters.endDate!.month,
        _filters.endDate!.day,
        23,
        59,
        59,
      );
      result = result
          .where((a) => !a.startDate.isBefore(s) && !a.startDate.isAfter(e))
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
      adaptivePageRoute<void>(
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
      adaptivePageRoute<void>(
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
          context.read<AppointmentController>().loadAppointments(reset: true);
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
                SliverToBoxAdapter(child: _buildHero(ctrl, theme, filtered)),
                SliverToBoxAdapter(
                  child: _buildStatsRow(ctrl, theme, filtered),
                ),
                SliverToBoxAdapter(
                  child: _buildPendingInvitesPill(ctrl, theme),
                ),
                SliverToBoxAdapter(child: _buildViewModeSection(theme)),
                if (_viewMode == CalendarViewMode.month ||
                    _viewMode == CalendarViewMode.week)
                  SliverToBoxAdapter(child: _buildCalendar(theme))
                else
                  SliverToBoxAdapter(child: _buildAgendaList(filtered, theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(child: _buildSelectedDayHeader(theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(child: _buildSelectedDayList(theme)),
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
                  ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
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
    final upcomingToday = todayAppts
        .where((a) => !a.endDate.isBefore(now))
        .toList();
    final next = upcomingToday.isNotEmpty
        ? upcomingToday.first
        : filtered
              .where((a) => a.startDate.isAfter(now))
              .fold<Appointment?>(
                null,
                (acc, a) => acc == null || a.startDate.isBefore(acc.startDate)
                    ? a
                    : acc,
              );

    final tomorrowCount = filtered
        .where((a) => _isSameDay(a.startDate, tomorrow))
        .length;

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
  /// Linha tipográfica de stats — substitui o row de 5 cards horizontais
  /// que parecia "lista de cards iguais" e poluía o topo da tela.
  ///
  /// Design editorial:
  /// - Cada coluna divide o espaço com `Expanded` (cabe 4 colunas em
  ///   telas estreitas; "Total" é dropado no menor breakpoint).
  /// - Número grande peso 900 com cor temática
  /// - Label uppercase fino abaixo
  /// - Linha accent sob o label como assinatura visual
  /// - Separadores verticais sutis entre colunas (não cards)
  /// - Tap em "Hoje" continua funcionando (foca o dia)
  Widget _buildStatsRow(
    AppointmentController ctrl,
    ThemeData theme,
    List<Appointment> filtered,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));

    final todayCount = filtered
        .where((a) => _isSameDay(a.startDate, today))
        .length;
    final weekCount = filtered
        .where(
          (a) => !a.startDate.isBefore(today) && a.startDate.isBefore(weekEnd),
        )
        .length;
    final pendingCount = filtered
        .where(
          (a) =>
              a.status == AppointmentStatus.scheduled ||
              a.status == AppointmentStatus.confirmed,
        )
        .length;
    final completedCount = filtered
        .where((a) => a.status == AppointmentStatus.completed)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Em telas largas (>=420px), cabe os 5 stats. Em telas estreitas,
          // dropa "Total" (que é equivalente a `filtered.length` e o user
          // já vê implícito na lista do dia).
          final compact = constraints.maxWidth < 420;
          final items = <_CalendarStatTile>[
            _CalendarStatTile(
              accent: AppColors.primary.primary,
              label: 'Hoje',
              value: todayCount,
              onTap: () => setState(() {
                _selectedDay = today;
                _focusedDay = today;
              }),
            ),
            _CalendarStatTile(
              accent: AppColors.status.info,
              label: '7 dias',
              value: weekCount,
            ),
            _CalendarStatTile(
              accent: AppColors.status.warning,
              label: 'Pendentes',
              value: pendingCount,
            ),
            _CalendarStatTile(
              accent: AppColors.status.success,
              label: 'Concluídos',
              value: completedCount,
            ),
            if (!compact)
              _CalendarStatTile(
                accent: AppColors.status.purple,
                label: 'Total',
                value: filtered.length,
              ),
          ];

          final divColor = ThemeHelpers.borderLightColor(
            context,
          ).withValues(alpha: 0.55);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Container(width: 1, height: 38, color: divColor),
                Expanded(child: items[i].render(context, theme)),
              ],
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PENDING INVITES PILL
  // ---------------------------------------------------------------------------
  Widget _buildPendingInvitesPill(AppointmentController ctrl, ThemeData theme) {
    final pending = ctrl.pendingInvites.length;
    if (pending == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.status.warning.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.status.warning.withOpacity(0.32)),
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
                      text:
                          'convite${pending > 1 ? 's' : ''} aguardando sua resposta',
                      style: TextStyle(color: ThemeHelpers.textColor(context)),
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
  /// Calendário modernizado — mantém `TableCalendar` por baixo mas com
  /// estética premium:
  /// - Container com gradient sutil accent no topo (não sólido cinza)
  /// - Header do mês em destaque com eyebrow + título grande
  /// - Chevrons em pill accent semitransparente, com microinteração
  /// - Days of week com letra única (`SEG TER QUA…`) em peso 900
  /// - Cells com transição AnimatedContainer e bordas refinadas
  /// - Markers de evento como mini-pills coloridas (não dots simples)
  Widget _buildCalendar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
          border: Border.all(
            color: ThemeHelpers.borderColor(
              context,
            ).withValues(alpha: isDark ? 0.55 : 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.18)
                  : const Color(0xFF1A2340).withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Gradient sutil no topo do calendário — dá sensação de
              // "luz" superior premium sem ser chamativo
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 70,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primary.withValues(alpha: isDark ? 0.10 : 0.05),
                          primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              TableCalendar<Appointment>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2032, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),
                calendarFormat: _tableFormat,
                startingDayOfWeek: StartingDayOfWeek.monday,
                locale: 'pt_BR',
                rowHeight: 54,
                daysOfWeekHeight: 36,
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
                  titleTextStyle:
                      theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        fontSize: 18,
                      ) ??
                      const TextStyle(),
                  leftChevronIcon: _buildChevronButton(
                    Icons.chevron_left_rounded,
                    primary,
                    isDark,
                  ),
                  rightChevronIcon: _buildChevronButton(
                    Icons.chevron_right_rounded,
                    primary,
                    isDark,
                  ),
                  headerPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  headerMargin: const EdgeInsets.only(bottom: 6),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    letterSpacing: 1.6,
                  ),
                  weekendStyle: TextStyle(
                    color: primary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    letterSpacing: 1.6,
                  ),
                  dowTextFormatter: (date, locale) {
                    // Iniciais fortes (S T Q…) em vez de "seg ter qua"
                    // — visual mais limpo no calendário compacto.
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
                    fontSize: 14,
                  ),
                  weekendTextStyle: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                calendarBuilders: CalendarBuilders<Appointment>(
                  defaultBuilder: (context, day, focused) =>
                      _dayCell(day, false, false, false),
                  todayBuilder: (context, day, focused) =>
                      _dayCell(day, false, true, false),
                  selectedBuilder: (context, day, focused) => _dayCell(
                    day,
                    true,
                    _isSameDay(day, DateTime.now()),
                    false,
                  ),
                  outsideBuilder: (context, day, focused) =>
                      _dayCell(day, false, false, true),
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    final isSelected = _isSameDay(_selectedDay, day);
                    // Quando o dia está selecionado (fundo accent),
                    // markers ficam brancos pra contrastar.
                    final markerColor = (Color base) =>
                        isSelected ? Colors.white : base;
                    return Positioned(
                      bottom: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: events.take(3).map((e) {
                          final c = AppointmentVisuals.colorFromHex(e.color);
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: markerColor(c),
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: c.withValues(alpha: 0.55),
                                        blurRadius: 4,
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
            ],
          ),
        ),
      ),
    );
  }

  /// Botão chevron premium para navegação de mês — pill accent
  /// semitransparente com sombra sutil.
  Widget _buildChevronButton(IconData icon, Color accent, bool isDark) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
        ),
      ),
      child: Icon(icon, color: accent, size: 22),
    );
  }

  /// Célula de dia do calendário.
  ///
  /// Estados:
  /// - **Selecionado**: gradient accent diagonal + sombra accent + texto branco
  /// - **Hoje (não selecionado)**: ring accent ao redor + accent suave de fundo
  /// - **Fim de semana**: cor secondary suave (não compete com dias úteis)
  /// - **Fora do mês**: opacity 0.4
  /// - **Default**: texto normal
  ///
  /// Tudo animado com `AnimatedContainer` 200ms — sensação de calendário
  /// "vivo" ao trocar seleção.
  Widget _dayCell(DateTime day, bool selected, bool isToday, bool outside) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color textColor;
    if (selected) {
      textColor = Colors.white;
    } else if (outside) {
      textColor = ThemeHelpers.textSecondaryColor(
        context,
      ).withValues(alpha: 0.4);
    } else if (isToday) {
      textColor = primary;
    } else if (isWeekend) {
      textColor = ThemeHelpers.textSecondaryColor(
        context,
      ).withValues(alpha: 0.85);
    } else {
      textColor = ThemeHelpers.textColor(context);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary,
                  Color.lerp(primary, Colors.black, 0.18) ?? primary,
                ],
              )
            : null,
        color: !selected && isToday
            ? primary.withValues(alpha: isDark ? 0.16 : 0.08)
            : null,
        borderRadius: BorderRadius.circular(13),
        border: !selected && isToday
            ? Border.all(color: primary.withValues(alpha: 0.55), width: 1.4)
            : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.42),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: textColor,
          fontWeight: selected || isToday ? FontWeight.w900 : FontWeight.w600,
          fontSize: 14.5,
          letterSpacing: -0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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
                color: ThemeHelpers.textSecondaryColor(
                  context,
                ).withOpacity(0.6),
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
// AGENDA HEADER — fluido, sem caixa, identidade própria.
//
// Esta tela NÃO usa o padrão "hero card" do Dashboard / CRM / Imóveis
// (eyebrow + título + subtítulo dentro de um container retângular). Aqui
// o conteúdo é solto, com hierarquia tipográfica editorial:
//
//   AGENDA · QUARTA-FEIRA                              ● 14:32
//
//   15 de outubro                                          ← manchete
//   3 compromissos hoje · 2 amanhã                        ← contexto
//
//   ─────────────────────────────────────────────         ← divisor gradient
//
//   PRÓXIMO · em 1h12
//
//   15:45 │ Visita ao apartamento Rua Gomes              ← tap → details
//         │ ● Visita    📍 Vila Olímpia                   →
// ===========================================================================

class _PremiumHero extends StatelessWidget {
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

  String _buildContextLine() {
    final parts = <String>[];
    if (todayCount > 0) {
      parts.add(
        '$todayCount ${todayCount == 1 ? "compromisso" : "compromissos"} hoje',
      );
    }
    if (tomorrowCount > 0) {
      parts.add('$tomorrowCount amanhã');
    }
    if (parts.isEmpty) {
      return 'Dia livre — bom momento para focar nos seus leads';
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;
    final now = DateTime.now();
    final weekday = DateFormat('EEEE', 'pt_BR').format(now);
    final monthDay = DateFormat("d 'de' MMMM", 'pt_BR').format(now);
    final timeNow = DateFormat('HH:mm').format(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Eyebrow + relógio (fluido, sem container) ───────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'AGENDA · ${weekday.toUpperCase()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _AgendaLiveClock(time: timeNow, color: primary),
            ],
          ),
          const SizedBox(height: 10),
          // ── Manchete: data por extenso ───────────────────────────────
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              monthDay,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -1.4,
                color: ThemeHelpers.textColor(context),
                height: 1,
                fontSize: 38,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Contexto do dia ───────────────────────────────────────────
          Text(
            _buildContextLine(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
              height: 1.35,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 22),
          // ── Divisor gradient (linha fina horizontal, fade) ───────────
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary.withOpacity(isDark ? 0.55 : 0.4),
                  ThemeHelpers.borderColor(context).withOpacity(0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
          const SizedBox(height: 22),
          // ── Próximo compromisso ou estado vazio ──────────────────────
          if (next != null)
            _AgendaNextFluid(next: next!, isDark: isDark, onTap: onTapNext)
          else
            _AgendaEmptyFluid(
              todayCount: todayCount,
              tomorrowCount: tomorrowCount,
              onTap: onTapEmpty,
            ),
        ],
      ),
    );
  }
}

/// Relógio vivo no topo do hero — bullet pulsante + horário monospace.
class _AgendaLiveClock extends StatelessWidget {
  final String time;
  final Color color;
  const _AgendaLiveClock({required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.55),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          time,
          style: theme.textTheme.labelLarge?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

/// Próximo compromisso fluido — sem caixa. Layout horizontal:
/// [hora gigante] [linha vertical fina] [info] [chevron].
class _AgendaNextFluid extends StatelessWidget {
  final Appointment next;
  final bool isDark;
  final VoidCallback onTap;
  const _AgendaNextFluid({
    required this.next,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppointmentVisuals.colorFromHex(next.color);
    final now = DateTime.now();
    final isHappening =
        now.isAfter(next.startDate) && now.isBefore(next.endDate);
    final relative = AppointmentVisuals.relativeTimeLabel(
      next.startDate,
      next.endDate,
    );
    final timeStr = AppointmentVisuals.formattedTime(next.startDate);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Eyebrow: PRÓXIMO · em 1h12 (ou AO VIVO)
              Row(
                children: [
                  Icon(
                    isHappening ? Icons.bolt_rounded : Icons.schedule_rounded,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      isHappening
                          ? 'AO VIVO · ${relative.toLowerCase()}'
                          : 'PRÓXIMO · ${relative.toLowerCase()}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Linha principal: hora + linha vertical fina + info + chevron
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeStr,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: -1.5,
                        height: 1,
                        fontSize: 44,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withOpacity(isDark ? 0.55 : 0.42),
                            color.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            next.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.2,
                              color: ThemeHelpers.textColor(context),
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppointmentVisuals.iconFor(next.type),
                                    size: 13,
                                    color: color,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    next.type.label,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                          fontSize: 11,
                                          letterSpacing: 0.1,
                                        ),
                                  ),
                                ],
                              ),
                              if (next.location != null &&
                                  next.location!.trim().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 13,
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 200,
                                      ),
                                      child: Text(
                                        next.location!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  ThemeHelpers.textSecondaryColor(
                                                    context,
                                                  ),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: color.withOpacity(isDark ? 0.85 : 0.7),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado vazio fluido — sem caixa, mantém a linguagem editorial da tela.
class _AgendaEmptyFluid extends StatelessWidget {
  final int todayCount;
  final int tomorrowCount;
  final VoidCallback onTap;
  const _AgendaEmptyFluid({
    required this.todayCount,
    required this.tomorrowCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasToday = todayCount > 0;
    final color = AppColors.status.success;

    final eyebrow = hasToday
        ? 'DIA CONCLUÍDO'
        : (tomorrowCount > 0 ? 'AMANHÃ NA SUA AGENDA' : 'AGENDA LIVRE');
    final headline = hasToday
        ? 'Sem mais compromissos hoje'
        : (tomorrowCount > 0
              ? 'Hoje livre — $tomorrowCount amanhã'
              : 'Sem compromissos à vista');
    final subtitle = hasToday
        ? 'Aproveite para revisar leads ou planejar amanhã.'
        : 'Toque abaixo para criar um novo compromisso.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    hasToday
                        ? Icons.celebration_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                headline,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.15,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Criar compromisso',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              child: AppointmentCard(appointment: appointment, onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile da linha de stats do calendário — um item da "manchete editorial"
/// que substitui o row de cards encapsulados.
class _CalendarStatTile {
  const _CalendarStatTile({
    required this.accent,
    required this.label,
    required this.value,
    this.onTap,
  });

  final Color accent;
  final String label;
  final int value;
  final VoidCallback? onTap;

  Widget render(BuildContext context, ThemeData theme) {
    final tileBody = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Número grande — protagonista visual
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
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
          // Label uppercase fino
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
          // Linha accent sob o label
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

    if (onTap == null) return tileBody;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: tileBody,
      ),
    );
  }
}
