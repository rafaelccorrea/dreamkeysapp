import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';

/// Página de criação de agendamento
class CreateAppointmentPage extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const CreateAppointmentPage({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
  });

  @override
  State<CreateAppointmentPage> createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentType _selectedType = AppointmentType.visit;
  AppointmentVisibility _selectedVisibility = AppointmentVisibility.private;
  String _selectedColor = '#3B82F6';
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;

  final List<String> _availableColors = [
    '#3B82F6', // Azul
    '#10B981', // Verde
    '#F59E0B', // Amarelo
    '#EF4444', // Vermelho
    '#8B5CF6', // Roxo
    '#06B6D4', // Ciano
    '#84CC16', // Lima
    '#F97316', // Laranja
    '#EC4899', // Rosa
    '#6366F1', // Índigo
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = widget.initialStartDate ?? now;
    _endDate = widget.initialEndDate ?? now.add(const Duration(hours: 1));
    _startTime = TimeOfDay.fromDateTime(_startDate!);
    _endTime = TimeOfDay.fromDateTime(_endDate!);
    
    // Adicionar listeners para validação em tempo real
    _titleController.addListener(_validateForm);
    _descriptionController.addListener(_validateForm);
    _notesController.addListener(_validateForm);
  }
  
  void _validateForm() {
    setState(() {});
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
      _validateForm();
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
      _validateForm();
    }
  }

  String? _validateDates() {
    if (_startDate == null || _endDate == null || _startTime == null || _endTime == null) {
      return 'Selecione data e horário de início e término';
    }

    final now = DateTime.now();
    final startDateTime = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    
    final endDateTime = DateTime(
      _endDate!.year,
      _endDate!.month,
      _endDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );

    if (startDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
      return 'A data/hora de início não pode estar no passado';
    }

    if (endDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
      return 'A data/hora de término não pode estar no passado';
    }

    if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
      return 'A data/hora de término deve ser posterior à data/hora de início';
    }

    return null;
  }
  
  /// Verifica se o formulário está válido
  bool _isFormValid() {
    // Título obrigatório
    if (_titleController.text.trim().isEmpty) {
      return false;
    }
    
    // Datas e horários obrigatórios
    if (_startDate == null || _endDate == null || _startTime == null || _endTime == null) {
      return false;
    }
    
    // Validar datas
    if (_validateDates() != null) {
      return false;
    }
    
    // Validar descrição (máximo 300 caracteres)
    if (_descriptionController.text.length > 300) {
      return false;
    }
    
    // Validar observações (máximo 300 caracteres)
    if (_notesController.text.length > 300) {
      return false;
    }
    
    return true;
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
      // Combinar data e hora para criar DateTime completo
      final startDateTime = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        _startTime!.hour,
        _startTime!.minute,
      );
      
      final endDateTime = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        _endTime!.hour,
        _endTime!.minute,
      );

      final controller = context.read<AppointmentController>();
      final success = await controller.createAppointment(
        CreateAppointmentData(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _selectedType,
          visibility: _selectedVisibility,
          startDate: startDateTime,
          endDate: endDateTime,
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
              content: const Text('Agendamento criado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.error ?? 'Erro ao criar agendamento'),
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

    return AppScaffold(
      title: 'Novo Agendamento',
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
              onChanged: (_) => _validateForm(),
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
              onChanged: (_) => _validateForm(),
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
            const SizedBox(height: 24),
            // Data e Hora Início
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
            if (_startDate != null && _startTime != null && _endDate != null && _endTime != null)
              Builder(
                builder: (context) {
                  final dateError = _validateDates();
                  if (dateError != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dateError,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.status.error,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            const SizedBox(height: 16),
            // Data e Hora Fim
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
              validator: (value) {
                if (value != null && value.length > 300) {
                  return 'Máximo de 300 caracteres';
                }
                return null;
              },
              onChanged: (_) => _validateForm(),
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
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            CustomButton(
              text: 'Criar Agendamento',
              icon: Icons.check,
              onPressed: (_isLoading || !_isFormValid()) ? null : _save,
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

