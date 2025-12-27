import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import 'edit_appointment_page.dart';

/// Página de detalhes do agendamento
class AppointmentDetailsPage extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailsPage({
    super.key,
    required this.appointmentId,
  });

  @override
  State<AppointmentDetailsPage> createState() => _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppointmentController>().loadAppointmentById(widget.appointmentId);
    });
  }

  Future<void> _deleteAppointment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este agendamento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final controller = context.read<AppointmentController>();
      final success = await controller.deleteAppointment(widget.appointmentId);

      if (mounted) {
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Agendamento excluído com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.error ?? 'Erro ao excluir agendamento'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');

    return AppScaffold(
      title: 'Detalhes do Agendamento',
      body: Consumer<AppointmentController>(
        builder: (context, controller, child) {
          if (controller.loading && controller.selectedAppointment == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final appointment = controller.selectedAppointment;
          if (appointment == null) {
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
                    controller.error ?? 'Agendamento não encontrado',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: 'Voltar',
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com cor
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(int.parse(appointment.color.replaceFirst('#', '0xFF')))
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color(int.parse(appointment.color.replaceFirst('#', '0xFF')))
                          .withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appointment.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildStatusChip(appointment.status, theme),
                        ],
                      ),
                      if (appointment.description != null &&
                          appointment.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          appointment.description!,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Informações gerais
                _buildInfoSection(
                  theme,
                  'Informações Gerais',
                  [
                    _buildInfoItem(
                      theme,
                      Icons.category,
                      'Tipo',
                      appointment.type.label,
                    ),
                    _buildInfoItem(
                      theme,
                      Icons.visibility,
                      'Visibilidade',
                      appointment.visibility.label,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Data e Horário
                _buildInfoSection(
                  theme,
                  'Data e Horário',
                  [
                    _buildInfoItem(
                      theme,
                      Icons.calendar_today,
                      'Data de Início',
                      '${dateFormat.format(appointment.startDate)} às ${timeFormat.format(appointment.startDate)}',
                    ),
                    _buildInfoItem(
                      theme,
                      Icons.calendar_today,
                      'Data de Término',
                      '${dateFormat.format(appointment.endDate)} às ${timeFormat.format(appointment.endDate)}',
                    ),
                    _buildInfoItem(
                      theme,
                      Icons.access_time,
                      'Duração',
                      _calculateDuration(appointment.startDate, appointment.endDate),
                    ),
                  ],
                ),
                if (appointment.location != null &&
                    appointment.location!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildInfoSection(
                    theme,
                    'Localização',
                    [
                      _buildInfoItem(
                        theme,
                        Icons.location_on,
                        'Local',
                        appointment.location!,
                      ),
                    ],
                  ),
                ],
                if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildInfoSection(
                    theme,
                    'Observações',
                    [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          appointment.notes!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                // Ações
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Editar',
                        icon: Icons.edit,
                        variant: ButtonVariant.secondary,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditAppointmentPage(appointmentId: appointment.id),
                            ),
                          ).then((_) {
                            controller.loadAppointmentById(widget.appointmentId);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomButton(
                        text: 'Excluir',
                        icon: Icons.delete,
                        variant: ButtonVariant.secondary,
                        onPressed: _deleteAppointment,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ThemeHelpers.borderColor(context),
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoItem(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _calculateDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration.inDays > 0) {
      return '${duration.inDays} dia(s)';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hora(s)';
    } else {
      return '${duration.inMinutes} minuto(s)';
    }
  }
}

