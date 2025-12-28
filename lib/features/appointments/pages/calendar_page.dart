import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import 'create_appointment_page.dart';
import 'appointment_details_page.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Página principal do calendário de agendamentos
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final TextEditingController _searchController = TextEditingController();
  late ValueNotifier<List<Appointment>> _selectedAppointments;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<String, List<Appointment>>? _cachedAppointmentsMap;
  List<Appointment>? _cachedAppointments;

  // Helper para normalizar data para string chave
  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _selectedAppointments = ValueNotifier([]);
    // Limpar cache antigo para evitar problemas de tipo
    _cachedAppointmentsMap = null;
    _cachedAppointments = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<AppointmentController>();
      controller.loadAppointments(reset: true);
      controller.loadPendingInvites();
      _selectedAppointments.value = _getAppointmentsForDay(_selectedDay);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _selectedAppointments.dispose();
    super.dispose();
  }

  List<Appointment> _getAppointmentsForDay(DateTime day) {
    final controller = context.read<AppointmentController>();
    final appointments = controller.filteredAppointments;

    // Usar string para comparação consistente
    final dayKey = _dateKey(day);

    return appointments.where((appointment) {
      final appointmentKey = _dateKey(appointment.startDate);
      return appointmentKey == dayKey;
    }).toList();
  }

  Map<String, List<Appointment>> _getAppointmentsMap() {
    final controller = context.read<AppointmentController>();
    final appointments = controller.filteredAppointments;

    // Se os agendamentos não mudaram e o cache é válido, retornar cache
    if (_cachedAppointments != null &&
        _cachedAppointmentsMap != null &&
        _listEquals(_cachedAppointments!, appointments)) {
      // Verificar se o cache tem o tipo correto
      if (_cachedAppointmentsMap is Map<String, List<Appointment>>) {
        return _cachedAppointmentsMap!;
      } else {
        // Cache com tipo antigo, limpar
        _cachedAppointmentsMap = null;
        _cachedAppointments = null;
      }
    }

    final map = <String, List<Appointment>>{};

    for (var appointment in appointments) {
      // Usar string como chave para evitar problemas de comparação de DateTime
      final key = _dateKey(appointment.startDate);

      if (map.containsKey(key)) {
        map[key]!.add(appointment);
      } else {
        map[key] = [appointment];
      }
    }

    // Cachear resultado
    _cachedAppointments = List.from(appointments);
    _cachedAppointmentsMap = map;

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Agendamentos',
      currentBottomNavIndex: 2, // Índice da aba de Agenda
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreateAppointmentPage(
                  initialStartDate: _selectedDay,
                  initialEndDate: _selectedDay.add(const Duration(hours: 1)),
                ),
              ),
            ).then((_) {
              context.read<AppointmentController>().loadAppointments(
                reset: true,
              );
            });
          },
          tooltip: 'Novo Agendamento',
        ),
      ],
      body: Consumer<AppointmentController>(
        builder: (context, controller, child) {
          if (controller.loading && controller.appointments.isEmpty) {
            return _buildCalendarSkeleton(context, theme);
          }

          if (controller.error != null && controller.appointments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.status.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.error!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: 'Tentar Novamente',
                    icon: Icons.refresh,
                    onPressed: () {
                      controller.loadAppointments(reset: true);
                    },
                  ),
                ],
              ),
            );
          }

          final appointmentsMap = _getAppointmentsMap();
          // Atualizar apenas se necessário
          final currentAppointments = _getAppointmentsForDay(_selectedDay);
          if (_selectedAppointments.value.length !=
                  currentAppointments.length ||
              !_listEquals(_selectedAppointments.value, currentAppointments)) {
            _selectedAppointments.value = currentAppointments;
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              // Calcular altura disponível para o calendário
              final screenHeight = MediaQuery.of(context).size.height;
              final appBarHeight = AppBar().preferredSize.height;
              final statusBarHeight = MediaQuery.of(context).padding.top;
              final bottomNavHeight =
                  60.0; // Altura aproximada da navegação inferior
              final searchHeight = 56.0; // Altura da barra de busca
              final statsHeight = 80.0; // Altura das estatísticas
              final padding = 32.0; // Padding total

              // Calendário ocupará quase toda a tela (deixando espaço para lista)
              final calendarHeight =
                  screenHeight -
                  appBarHeight -
                  statusBarHeight -
                  bottomNavHeight -
                  searchHeight -
                  statsHeight -
                  padding -
                  250; // Espaço para lista de agendamentos (aumentado)

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // Barra de busca
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar agendamentos...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    controller.setSearchTerm('');
                                    setState(() {
                                      _selectedAppointments.value =
                                          _getAppointmentsForDay(_selectedDay);
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          controller.setSearchTerm(value);
                          setState(() {
                            _selectedAppointments.value =
                                _getAppointmentsForDay(_selectedDay);
                          });
                        },
                      ),
                    ),

                    // Estatísticas
                    _buildStatistics(controller, theme),

                    // Calendário
                    Container(
                      height: calendarHeight > 320 ? calendarHeight : 420,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.cardBackgroundColor(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      child: RepaintBoundary(
                        child: TableCalendar<Appointment>(
                          key: ValueKey(
                            'calendar_${_focusedDay.year}_${_focusedDay.month}_${_calendarFormat}',
                          ),
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2030, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          calendarFormat: _calendarFormat,
                          eventLoader: (day) {
                            // Usar string como chave para corresponder ao Map
                            final key = _dateKey(day);
                            return appointmentsMap[key] ?? [];
                          },
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          locale: 'pt_BR',
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Mês',
                            CalendarFormat.twoWeeks: '2 Semanas',
                            CalendarFormat.week: 'Semana',
                          },
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            weekendTextStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            defaultTextStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            selectedTextStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            todayTextStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: AppColors.primary.primary,
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: BoxDecoration(
                              color: AppColors.primary.primary.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            markerDecoration: BoxDecoration(
                              color: AppColors.primary.primary,
                              shape: BoxShape.circle,
                            ),
                            markersMaxCount: 3,
                            markerSize: 6,
                            canMarkersOverflow: false,
                            cellPadding: const EdgeInsets.all(8),
                            cellMargin: const EdgeInsets.all(2),
                          ),
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, date, events) {
                              if (events.isNotEmpty) {
                                return Positioned(
                                  bottom: 4,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: events
                                        .take(3)
                                        .map(
                                          (event) => Container(
                                            key: ValueKey(
                                              'marker_${date.year}_${date.month}_${date.day}_${event.id}',
                                            ),
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1.5,
                                            ),
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          headerStyle: HeaderStyle(
                            formatButtonVisible: true,
                            titleCentered: true,
                            formatButtonShowsNext: false,
                            formatButtonDecoration: BoxDecoration(
                              color: AppColors.primary.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            formatButtonTextStyle: TextStyle(
                              color: AppColors.primary.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            leftChevronIcon: Icon(
                              Icons.chevron_left,
                              color: ThemeHelpers.textColor(context),
                              size: 28,
                            ),
                            rightChevronIcon: Icon(
                              Icons.chevron_right,
                              color: ThemeHelpers.textColor(context),
                              size: 28,
                            ),
                            titleTextStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                            leftChevronPadding: const EdgeInsets.all(6),
                            rightChevronPadding: const EdgeInsets.all(6),
                            headerPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            weekendStyle: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          daysOfWeekHeight: 40,
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                              _selectedAppointments.value =
                                  _getAppointmentsForDay(selectedDay);
                            });
                          },
                          onFormatChanged: (format) {
                            setState(() {
                              _calendarFormat = format;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            setState(() {
                              _focusedDay = focusedDay;
                            });
                          },
                        ),
                      ),
                    ),

                    // Lista de agendamentos do dia selecionado
                    ValueListenableBuilder<List<Appointment>>(
                      valueListenable: _selectedAppointments,
                      builder: (context, appointments, _) {
                        if (appointments.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_busy,
                                    size: 48,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhum agendamento em ${DateFormat('dd/MM/yyyy').format(_selectedDay)}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.7),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Toque no botão + para criar',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.5),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Container(
                          constraints: const BoxConstraints(minHeight: 200),
                          child: RefreshIndicator(
                            onRefresh: () async {
                              await controller.loadAppointments(reset: true);
                              setState(() {
                                _selectedAppointments.value =
                                    _getAppointmentsForDay(_selectedDay);
                              });
                            },
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: appointments.length,
                              itemBuilder: (context, index) {
                                final appointment = appointments[index];
                                return _buildAppointmentCard(
                                  appointment,
                                  theme,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatistics(AppointmentController controller, ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));

    final todayCount = controller.appointments.where((a) {
      final start = DateTime(
        a.startDate.year,
        a.startDate.month,
        a.startDate.day,
      );
      return start == today;
    }).length;

    final weekCount = controller.appointments.where((a) {
      return a.startDate.isAfter(today.subtract(const Duration(days: 1))) &&
          a.startDate.isBefore(weekEnd);
    }).length;

    final completedCount = controller.appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              'Total',
              controller.appointments.length.toString(),
              theme,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: ThemeHelpers.borderColor(context),
          ),
          Expanded(child: _buildStatItem('Hoje', todayCount.toString(), theme)),
          Container(
            width: 1,
            height: 40,
            color: ThemeHelpers.borderColor(context),
          ),
          Expanded(
            child: _buildStatItem('Semana', weekCount.toString(), theme),
          ),
          Container(
            width: 1,
            height: 40,
            color: ThemeHelpers.borderColor(context),
          ),
          Expanded(
            child: _buildStatItem(
              'Concluídos',
              completedCount.toString(),
              theme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildAppointmentCard(Appointment appointment, ThemeData theme) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');
    final isDark = theme.brightness == Brightness.dark;
    final appointmentColor = Color(
      int.parse(appointment.color.replaceFirst('#', '0xFF')),
    );

    return Container(
      key: ValueKey(appointment.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AppointmentDetailsPage(appointmentId: appointment.id),
              ),
            ).then((_) {
              context.read<AppointmentController>().loadAppointments(
                reset: true,
              );
              setState(() {
                _selectedAppointments.value = _getAppointmentsForDay(
                  _selectedDay,
                );
              });
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com linha colorida e status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linha colorida vertical
                    Container(
                      width: 4,
                      height: 60,
                      decoration: BoxDecoration(
                        color: appointmentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Título
                          Text(
                            appointment.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                              fontSize: 18,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          // Status
                          _buildStatusChip(appointment.status, theme),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Data e hora em card moderno
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        appointmentColor.withOpacity(0.08),
                        appointmentColor.withOpacity(0.03),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: appointmentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 28,
                          color: appointmentColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${timeFormat.format(appointment.startDate)} - ${timeFormat.format(appointment.endDate)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: ThemeHelpers.textColor(context),
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 16,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  dateFormat.format(appointment.startDate),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Localização
                if (appointment.location != null &&
                    appointment.location!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 20,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appointment.location!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Descrição resumida
                if (appointment.description != null &&
                    appointment.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      appointment.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Footer com ação
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Ver detalhes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appointmentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: appointmentColor,
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

  Widget _buildStatusChip(AppointmentStatus status, ThemeData theme) {
    Color color;
    switch (status) {
      case AppointmentStatus.scheduled:
        color = AppColors.status.warning;
        break;
      case AppointmentStatus.confirmed:
        color = AppColors.status.info;
        break;
      case AppointmentStatus.inProgress:
        color = AppColors.primary.primary;
        break;
      case AppointmentStatus.completed:
        color = AppColors.status.success;
        break;
      case AppointmentStatus.cancelled:
      case AppointmentStatus.noShow:
        color = AppColors.status.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildCalendarSkeleton(BuildContext context, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final appBarHeight = AppBar().preferredSize.height;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        final bottomNavHeight = 60.0;
        final searchHeight = 56.0;
        final statsHeight = 80.0;
        final padding = 32.0;

        final calendarHeight =
            screenHeight -
            appBarHeight -
            statusBarHeight -
            bottomNavHeight -
            searchHeight -
            statsHeight -
            padding -
            200;

        return SingleChildScrollView(
          child: Column(
            children: [
              // Barra de busca skeleton
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SkeletonBox(height: 48, borderRadius: 12),
              ),

              // Estatísticas skeleton
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
                child: Row(
                  children: List.generate(
                    4,
                    (index) => Expanded(
                      child: Column(
                        children: [
                          SkeletonBox(width: 30, height: 24, borderRadius: 4),
                          const SizedBox(height: 8),
                          SkeletonBox(width: 50, height: 14, borderRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Calendário skeleton
              Container(
                height: calendarHeight > 400 ? calendarHeight : 500,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
                child: Column(
                  children: [
                    // Header skeleton
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SkeletonBox(width: 30, height: 30, borderRadius: 8),
                          SkeletonBox(width: 150, height: 24, borderRadius: 8),
                          SkeletonBox(width: 30, height: 30, borderRadius: 8),
                        ],
                      ),
                    ),
                    // Dias da semana skeleton
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(
                          7,
                          (index) => SkeletonBox(
                            width: 30,
                            height: 20,
                            borderRadius: 4,
                          ),
                        ),
                      ),
                    ),
                    // Grid de dias skeleton
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 1,
                            ),
                        itemCount: 35,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: SkeletonBox(borderRadius: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Lista skeleton
              Container(
                constraints: const BoxConstraints(minHeight: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: Column(
                  children: List.generate(
                    3,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SkeletonBox(height: 80, borderRadius: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
