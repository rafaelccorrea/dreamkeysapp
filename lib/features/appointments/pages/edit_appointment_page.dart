import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';

/// Página de edição de agendamento
class EditAppointmentPage extends StatefulWidget {
  final String appointmentId;

  const EditAppointmentPage({
    super.key,
    required this.appointmentId,
  });

  @override
  State<EditAppointmentPage> createState() => _EditAppointmentPageState();
}

class _EditAppointmentPageState extends State<EditAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentType? _selectedType;
  AppointmentStatus? _selectedStatus;
  AppointmentVisibility? _selectedVisibility;
  String? _selectedColor;
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;
  bool _isLoadingAppointment = true;

  final List<String> _availableColors = [
    '#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6',
    '#06B6D4', '#84CC16', '#F97316', '#EC4899', '#6366F1',
  ];

  @override
  void initState() {
    super.initState();
    _loadAppointment();
  }

  Future<void> _loadAppointment() async {
    final controller = context.read<AppointmentController>();
    await controller.loadAppointmentById(widget.appointmentId);

    if (controller.selectedAppointment != null) {
      final appointment = controller.selectedAppointment!;
      _titleController.text = appointment.title;
      _descriptionController.text = appointment.description ?? '';
      _locationController.text = appointment.location ?? '';
      _notesController.text = appointment.notes ?? '';
      _selectedType = appointment.type;
      _selectedStatus = appointment.status;
      _selectedVisibility = appointment.visibility;
      _selectedColor = appointment.color;
      _startDate = appointment.startDate;
      _endDate = appointment.endDate;
      _startTime = TimeOfDay.fromDateTime(appointment.startDate);
      _endTime = TimeOfDay.fromDateTime(appointment.endDate);
    }

    setState(() {
      _isLoadingAppointment = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate! : _endDate!,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _startTime?.hour ?? 0,
            _startTime?.minute ?? 0,
          );
        } else {
          _endDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _endTime?.hour ?? 0,
            _endTime?.minute ?? 0,
          );
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startTime ?? TimeOfDay.now())
          : (_endTime ?? TimeOfDay.now()),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
          _startDate = DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
            picked.hour,
            picked.minute,
          );
        } else {
          _endTime = picked;
          _endDate = DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            picked.hour,
            picked.minute,
          );
        }
      });
    }
  }

  String? _validateDates() {
    if (_startDate == null || _endDate == null) {
      return 'Selecione data e horário de início e término';
    }

    if (_endDate!.isBefore(_startDate!) || _endDate!.isAtSameMomentAs(_startDate!)) {
      return 'A data/hora de término deve ser posterior à data/hora de início';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final dateError = _validateDates();
    if (dateError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dateError),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final controller = context.read<AppointmentController>();
      final success = await controller.updateAppointment(
        widget.appointmentId,
        UpdateAppointmentData(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _selectedType,
          status: _selectedStatus,
          visibility: _selectedVisibility,
          startDate: _startDate,
          endDate: _endDate,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          color: _selectedColor,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Agendamento atualizado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.error ?? 'Erro ao atualizar agendamento'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');

    if (_isLoadingAppointment) {
      return AppScaffold(
        title: 'Editar Agendamento',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return AppScaffold(
      title: 'Editar Agendamento',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CustomTextField(
              label: 'Título *',
              controller: _titleController,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Campo obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Descrição',
              controller: _descriptionController,
              maxLines: 3,
              validator: (value) {
                if (value != null && value.length > 300) {
                  return 'Máximo de 300 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Tipo
            Text(
              'Tipo *',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppointmentType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Text(type.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedType = type;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Status
            Text(
              'Status',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppointmentStatus.values.map((status) {
                final isSelected = _selectedStatus == status;
                return ChoiceChip(
                  label: Text(status.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedStatus = status;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            // Data e Hora
            Text(
              'Data e Hora de Início *',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(context, true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_startDate != null
                        ? dateFormat.format(_startDate!)
                        : 'Selecionar data'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectTime(context, true),
                    icon: const Icon(Icons.access_time),
                    label: Text(_startTime != null
                        ? timeFormat.format(DateTime(
                            2000, 1, 1, _startTime!.hour, _startTime!.minute))
                        : 'Selecionar hora'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Data e Hora de Término *',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(context, false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_endDate != null
                        ? dateFormat.format(_endDate!)
                        : 'Selecionar data'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectTime(context, false),
                    icon: const Icon(Icons.access_time),
                    label: Text(_endTime != null
                        ? timeFormat.format(DateTime(
                            2000, 1, 1, _endTime!.hour, _endTime!.minute))
                        : 'Selecionar hora'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Local',
              controller: _locationController,
              prefixIcon: const Icon(Icons.location_on),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Observações',
              controller: _notesController,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            // Visibilidade
            Text(
              'Visibilidade',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AppointmentVisibility.values.map((visibility) {
                final isSelected = _selectedVisibility == visibility;
                return ChoiceChip(
                  label: Text(visibility.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedVisibility = visibility;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            // Cor
            Text(
              'Cor do Agendamento',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableColors.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            CustomButton(
              text: 'Salvar Alterações',
              icon: Icons.save,
              onPressed: _isLoading ? null : _save,
              isLoading: _isLoading,
              isFullWidth: true,
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Cancelar',
              variant: ButtonVariant.secondary,
              icon: Icons.close,
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

