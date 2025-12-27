import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
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
  Map<DateTime, List<Appointment>>? _cachedAppointmentsMap;
  List<Appointment>? _cachedAppointments;

  @override
  void initState() {
    super.initState();
    _selectedAppointments = ValueNotifier([]);
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
    
    return appointments.where((appointment) {
      final appointmentDate = DateTime(
        appointment.startDate.year,
        appointment.startDate.month,
        appointment.startDate.day,
      );
      final dayDate = DateTime(day.year, day.month, day.day);
      return appointmentDate == dayDate;
    }).toList();
  }

  Map<DateTime, List<Appointment>> _getAppointmentsMap() {
    final controller = context.read<AppointmentController>();
    final appointments = controller.filteredAppointments;
    
    // Se os agendamentos não mudaram, retornar cache
    if (_cachedAppointments != null && 
        _listEquals(_cachedAppointments!, appointments)) {
      return _cachedAppointmentsMap!;
    }
    
    final map = <DateTime, List<Appointment>>{};

    for (var appointment in appointments) {
      final date = DateTime(
        appointment.startDate.year,
        appointment.startDate.month,
        appointment.startDate.day,
      );
      
      if (map.containsKey(date)) {
        map[date]!.add(appointment);
      } else {
        map[date] = [appointment];
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
              context.read<AppointmentController>().loadAppointments(reset: true);
            });
          },
          tooltip: 'Novo Agendamento',
        ),
      ],
      body: Consumer<AppointmentController>(
        builder: (context, controller, child) {
          if (controller.loading && controller.appointments.isEmpty) {
            return const Center(child: CircularProgressIndicator());
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
          if (_selectedAppointments.value.length != currentAppointments.length ||
              !_listEquals(_selectedAppointments.value, currentAppointments)) {
            _selectedAppointments.value = currentAppointments;
          }

          return Column(
            children: [
              // Barra de busca
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                _selectedAppointments.value = _getAppointmentsForDay(_selectedDay);
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    controller.setSearchTerm(value);
                    setState(() {
                      _selectedAppointments.value = _getAppointmentsForDay(_selectedDay);
                    });
                  },
                ),
              ),

              // Estatísticas
              _buildStatistics(controller, theme),

              // Calendário
              Container(
                constraints: const BoxConstraints(maxHeight: 270),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context),
                  ),
                ),
                child: ClipRect(
                  child: TableCalendar<Appointment>(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  calendarFormat: _calendarFormat,
                  eventLoader: (day) {
                    final key = DateTime(day.year, day.month, day.day);
                    return appointmentsMap[key] ?? [];
                  },
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  locale: 'pt_BR',
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    weekendTextStyle: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 13,
                    ),
                    defaultTextStyle: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 13,
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
                    markerSize: 5,
                    canMarkersOverflow: true,
                    cellPadding: EdgeInsets.zero,
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    leftChevronIcon: Icon(
                      Icons.chevron_left,
                      color: ThemeHelpers.textColor(context),
                      size: 20,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right,
                      color: ThemeHelpers.textColor(context),
                      size: 20,
                    ),
                    titleTextStyle: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    leftChevronPadding: const EdgeInsets.all(4),
                    rightChevronPadding: const EdgeInsets.all(4),
                    headerPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    weekendStyle: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                      _selectedAppointments.value = _getAppointmentsForDay(selectedDay);
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
              Expanded(
                child: ValueListenableBuilder<List<Appointment>>(
                  valueListenable: _selectedAppointments,
                  builder: (context, appointments, child) {
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
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum agendamento em ${DateFormat('dd/MM/yyyy').format(_selectedDay)}',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Toque no botão + para criar',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        await controller.loadAppointments(reset: true);
                        setState(() {
                          _selectedAppointments.value = _getAppointmentsForDay(_selectedDay);
                        });
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: appointments.length,
                        itemBuilder: (context, index) {
                          final appointment = appointments[index];
                          return _buildAppointmentCard(appointment, theme);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
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
      final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
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
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem('Total', controller.appointments.length.toString(), theme),
          ),
          Container(
            width: 1,
            height: 40,
            color: ThemeHelpers.borderColor(context),
          ),
          Expanded(
            child: _buildStatItem('Hoje', todayCount.toString(), theme),
          ),
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
            child: _buildStatItem('Concluídos', completedCount.toString(), theme),
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
    final appointmentColor = Color(int.parse(appointment.color.replaceFirst('#', '0xFF')));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(appointmentId: appointment.id),
            ),
          ).then((_) {
            context.read<AppointmentController>().loadAppointments(reset: true);
            setState(() {
              _selectedAppointments.value = _getAppointmentsForDay(_selectedDay);
            });
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com título e status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: appointmentColor.withValues(alpha: 0.1),
                border: Border(
                  left: BorderSide(
                    color: appointmentColor,
                    width: 4,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.event_outlined,
                              size: 18,
                              color: appointmentColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                appointment.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeHelpers.textColor(context),
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusChip(appointment.status, theme),
                ],
              ),
            ),

            // Data e hora
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: appointmentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.access_time,
                        size: 24,
                        color: appointmentColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${timeFormat.format(appointment.startDate)} - ${timeFormat.format(appointment.endDate)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateFormat.format(appointment.startDate),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                  fontSize: 14,
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
            ),

            // Localização
            if (appointment.location != null && appointment.location!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appointment.location!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Footer com indicador de navegação
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Toque para ver detalhes',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
