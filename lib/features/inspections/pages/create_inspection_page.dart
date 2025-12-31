import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/masked_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/utils/masks.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/inspection_model.dart';
import '../services/inspection_service.dart';
import '../widgets/cpf_cnpj_text_field.dart';

/// Página de criação de vistoria
class CreateInspectionPage extends StatefulWidget {
  const CreateInspectionPage({super.key});

  @override
  State<CreateInspectionPage> createState() => _CreateInspectionPageState();
}

class _CreateInspectionPageState extends State<CreateInspectionPage> {
  final _formKey = GlobalKey<FormState>();
  final InspectionService _inspectionService = InspectionService.instance;

  // Controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _observationsController = TextEditingController();
  final _valueController = TextEditingController();
  final _responsibleNameController = TextEditingController();
  final _responsibleDocumentController = TextEditingController();
  final _responsiblePhoneController = TextEditingController();

  // Estados
  InspectionType _selectedType = InspectionType.entry;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  String? _selectedInspectorId;
  String? _selectedInspectorName;
  bool _isLoading = false;
  bool _isLoadingUsers = false;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    // Inicializar data para hoje
    final now = DateTime.now();
    _scheduledDate = now;
    _scheduledTime = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _observationsController.dispose();
    _valueController.dispose();
    _responsibleNameController.dispose();
    _responsibleDocumentController.dispose();
    _responsiblePhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      // Buscar usuários da empresa para seleção de vistoriador
      final response = await ApiService.instance.get<dynamic>(
        '/chat/company/users',
      );

      if (mounted && response.success && response.data != null) {
        List<Map<String, dynamic>> users = [];
        if (response.data is List) {
          users = (response.data as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        }
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      } else {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _selectScheduledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('pt', 'BR'),
    );

    if (picked != null) {
      setState(() {
        _scheduledDate = picked;
      });
    }
  }

  Future<void> _selectScheduledTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? now,
    );

    if (picked != null) {
      setState(() {
        _scheduledTime = picked;
      });
    }
  }

  Future<void> _selectInspector() async {
    if (_users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum usuário disponível')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Selecionar Vistoriador',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final userName = user['name']?.toString() ?? '';
                  final userEmail = user['email']?.toString() ?? '';
                  final userId = user['id']?.toString() ?? '';
                  final isSelected = _selectedInspectorId == userId;

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(userName),
                    subtitle: Text(userEmail),
                    trailing: isSelected
                        ? Icon(Icons.check, color: AppColors.primary.primary)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      Navigator.pop(context, user);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedInspectorId = selected['id']?.toString();
        _selectedInspectorName = selected['name']?.toString();
      });
    }
  }

  double? _parseValue() {
    if (_valueController.text.trim().isEmpty) return null;

    // Remove "R$ " e substitui vírgula por ponto
    final cleanValue = _valueController.text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    final value = double.tryParse(cleanValue);
    return value != null && value > 0 ? value : null;
  }

  DateTime? _getScheduledDateTime() {
    if (_scheduledDate == null || _scheduledTime == null) return null;

    return DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _scheduledTime!.hour,
      _scheduledTime!.minute,
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final scheduledDateTime = _getScheduledDateTime();
    if (scheduledDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione data e horário agendados'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    // Validar que a data não é no passado
    if (scheduledDateTime.isBefore(
      DateTime.now().subtract(const Duration(minutes: 1)),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A data agendada não pode ser no passado'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione uma propriedade'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dto = CreateInspectionDto(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        type: _selectedType,
        scheduledDate: scheduledDateTime,
        propertyId: _selectedPropertyId!,
        inspectorId: _selectedInspectorId,
        value: _parseValue(),
        responsibleName: _responsibleNameController.text.trim().isEmpty
            ? null
            : _responsibleNameController.text.trim(),
        responsibleDocument: _responsibleDocumentController.text.trim().isEmpty
            ? null
            : Masks.unmaskAll(_responsibleDocumentController.text.trim()),
        responsiblePhone: _responsiblePhoneController.text.trim().isEmpty
            ? null
            : Masks.unmaskPhone(_responsiblePhoneController.text.trim()),
        observations: _observationsController.text.trim().isEmpty
            ? null
            : _observationsController.text.trim(),
      );

      final response = await _inspectionService.createInspection(dto);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (response.success && response.data != null) {
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.inspectionDetails(response.data!.id),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Vistoria criada com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar vistoria'),
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

    return AppScaffold(
      title: 'Nova Vistoria',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Título
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

            // Descrição
            CustomTextField(
              label: 'Descrição',
              controller: _descriptionController,
              maxLines: 3,
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
              children: InspectionType.values.map((type) {
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

            // Data e Hora Agendada
            Text(
              'Data e Hora Agendada *',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _selectScheduledDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _scheduledDate != null
                          ? dateFormat.format(_scheduledDate!)
                          : 'Selecionar data',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _selectScheduledTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      _scheduledTime != null
                          ? '${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                          : 'Selecionar hora',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Propriedade
            EntitySelector(
              type: 'property',
              selectedId: _selectedPropertyId,
              selectedName: _selectedPropertyName,
              onSelected: (id, name) {
                setState(() {
                  _selectedPropertyId = id;
                  _selectedPropertyName = name;
                });
              },
            ),
            const SizedBox(height: 16),

            // Vistoriador (opcional)
            InkWell(
              onTap: _isLoadingUsers ? null : _selectInspector,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Vistoriador',
                  hintText: 'Selecione um vistoriador (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person),
                  suffixIcon: _isLoadingUsers
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.arrow_drop_down),
                ),
                child: Text(
                  _selectedInspectorName ??
                      'Selecione um vistoriador (opcional)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _selectedInspectorName != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Valor
            MaskedTextField(
              label: 'Valor',
              controller: _valueController,
              maskType: MaskType.money,
              hint: 'R\$ 0,00',
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final parsed = _parseValue();
                  if (parsed == null || parsed <= 0) {
                    return 'Valor deve ser maior que zero';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Dados do Responsável
            Text(
              'Dados do Responsável (Opcional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            CustomTextField(
              label: 'Nome do Responsável',
              controller: _responsibleNameController,
            ),
            const SizedBox(height: 16),

            CpfCnpjTextField(
              label: 'Documento (CPF/CNPJ)',
              controller: _responsibleDocumentController,
            ),
            const SizedBox(height: 16),

            MaskedTextField(
              label: 'Telefone',
              controller: _responsiblePhoneController,
              maskType: MaskType.phone,
              hint: '(00) 00000-0000',
            ),
            const SizedBox(height: 24),

            // Observações
            CustomTextField(
              label: 'Observações',
              controller: _observationsController,
              maxLines: 4,
            ),
            const SizedBox(height: 32),

            // Botões
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    text: 'Salvar',
                    onPressed: _isLoading ? null : _handleSave,
                    isLoading: _isLoading,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                    child: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
