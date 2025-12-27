import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import 'create_appointment_page.dart';
import 'appointment_details_page.dart';

/// Página principal do calendário de agendamentos
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<AppointmentController>();
      controller.loadAppointments(reset: true);
      controller.loadPendingInvites();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final controller = context.read<AppointmentController>();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!controller.loadingMore && controller.hasMore) {
        controller.loadAppointments();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AppScaffold(
      title: 'Agendamentos',
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateAppointmentPage(),
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

          final appointments = controller.filteredAppointments;

          return Column(
            children: [
              // Barra de busca
              Padding(
                padding: const EdgeInsets.all(16),
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
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    controller.setSearchTerm(value);
                  },
                ),
              ),

              // Estatísticas
              _buildStatistics(controller, theme),

              // Lista de agendamentos
              Expanded(
                child: appointments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhum agendamento encontrado',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              controller.searchTerm.isNotEmpty
                                  ? 'Tente ajustar sua busca'
                                  : 'Crie seu primeiro agendamento',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await controller.loadAppointments(reset: true);
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: appointments.length + (controller.loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= appointments.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final appointment = appointments[index];
                            return _buildAppointmentCard(appointment, theme);
                          },
                        ),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: _buildStatItem('Esta Semana', weekCount.toString(), theme),
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
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentCard(Appointment appointment, ThemeData theme) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppointmentDetailsPage(appointmentId: appointment.id),
            ),
          ).then((_) {
            context.read<AppointmentController>().loadAppointments(reset: true);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(int.parse(appointment.color.replaceFirst('#', '0xFF'))),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appointment.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${dateFormat.format(appointment.startDate)} às ${timeFormat.format(appointment.startDate)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(appointment.status, theme),
                ],
              ),
              if (appointment.description != null && appointment.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  appointment.description!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (appointment.location != null && appointment.location!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        appointment.location!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

