import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/masked_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/inspection_model.dart';
import '../services/inspection_service.dart';
import '../widgets/cpf_cnpj_text_field.dart';

/// Página de edição de vistoria
class EditInspectionPage extends StatefulWidget {
  final String inspectionId;

  const EditInspectionPage({
    super.key,
    required this.inspectionId,
  });

  @override
  State<EditInspectionPage> createState() => _EditInspectionPageState();
}

class _EditInspectionPageState extends State<EditInspectionPage> {
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
  Inspection? _inspection;
  InspectionType _selectedType = InspectionType.entry;
  InspectionStatus? _selectedStatus;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  String? _selectedInspectorId;
  String? _selectedInspectorName;
  bool _isLoading = false;
  bool _isLoadingInspection = true;
  bool _isLoadingUsers = false;
  List<Map<String, dynamic>> _users = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInspection();
    _loadUsers();
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

  Future<void> _loadInspection() async {
    setState(() {
      _isLoadingInspection = true;
      _errorMessage = null;
    });

    try {
      final response = await _inspectionService.getInspectionById(
        widget.inspectionId,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          final inspection = response.data!;
          setState(() {
            _inspection = inspection;
            _titleController.text = inspection.title;
            _descriptionController.text = inspection.description ?? '';
            _observationsController.text = inspection.observations ?? '';
            _selectedType = inspection.type;
            _selectedStatus = inspection.status;
            _scheduledDate = inspection.scheduledDate;
            _scheduledTime = TimeOfDay(
              hour: inspection.scheduledDate.hour,
              minute: inspection.scheduledDate.minute,
            );
            _selectedPropertyId = inspection.propertyId;
            _selectedPropertyName = inspection.property?['title']?.toString();
            _selectedInspectorId = inspection.inspectorId;
            _selectedInspectorName = inspection.inspector?['name']?.toString();
            
            if (inspection.value != null) {
              final currencyFormat = NumberFormat.currency(
                locale: 'pt_BR',
                symbol: 'R\$',
                decimalDigits: 2,
              );
              _valueController.text = currencyFormat.format(inspection.value);
            }
            
            _responsibleNameController.text = inspection.responsibleName ?? '';
            _responsibleDocumentController.text = inspection.responsibleDocument ?? '';
            _responsiblePhoneController.text = inspection.responsiblePhone ?? '';
            
            _isLoadingInspection = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar vistoria';
            _isLoadingInspection = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro de conexão: ${e.toString()}';
          _isLoadingInspection = false;
        });
      }
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
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
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _scheduledDate = picked;
      });
    }
  }

  Future<void> _selectScheduledTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _scheduledTime = picked;
      });
    }
  }

  Future<void> _selectInspector() async {
    if (_isLoadingUsers) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.person),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Selecionar Vistoriador',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                  final userName = user['name']?.toString() ?? 'Sem nome';
                  final userId = user['id']?.toString() ?? '';
                  final isSelected = userId == _selectedInspectorId;

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(userName),
                    subtitle: user['email'] != null
                        ? Text(user['email'].toString())
                        : null,
                    selected: isSelected,
                    selectedTileColor:
                        AppColors.primary.primary.withValues(alpha: 0.1),
                    onTap: () {
                      Navigator.pop(context, {
                        'id': userId,
                        'name': userName,
                      });
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
        _selectedInspectorId = selected['id'];
        _selectedInspectorName = selected['name'];
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
    return value;
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final scheduledDateTime = _getScheduledDateTime();
    if (scheduledDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Data e hora agendada são obrigatórias'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    if (_selectedPropertyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Propriedade é obrigatória'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final updateData = UpdateInspectionDto(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        type: _selectedType,
        status: _selectedStatus,
        scheduledDate: scheduledDateTime,
        propertyId: _selectedPropertyId,
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

      final response = await _inspectionService.updateInspection(
        widget.inspectionId,
        updateData,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (response.success && response.data != null) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Vistoria atualizada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar vistoria'),
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

    if (_isLoadingInspection) {
      return AppScaffold(
        title: 'Editar Vistoria',
        body: _buildSkeleton(context),
      );
    }

    if (_errorMessage != null) {
      return AppScaffold(
        title: 'Editar Vistoria',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadInspection,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_inspection == null) {
      return AppScaffold(
        title: 'Editar Vistoria',
        body: const Center(child: Text('Vistoria não encontrada')),
      );
    }

    return AppScaffold(
      title: 'Editar Vistoria',
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

            // Status
            Text(
              'Status *',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: InspectionStatus.values.map((status) {
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
                  _selectedInspectorName ?? 'Selecione um vistoriador (opcional)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _selectedInspectorName != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
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

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          SkeletonText(width: 200, height: 20, margin: const EdgeInsets.only(bottom: 16)),
          // Campos
          ...List.generate(8, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 120, height: 16, margin: const EdgeInsets.only(bottom: 8)),
                SkeletonBox(height: 48, borderRadius: 12),
              ],
            ),
          )),
          // Botões
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 48, borderRadius: 12, margin: const EdgeInsets.only(bottom: 12)),
          SkeletonBox(width: double.infinity, height: 48, borderRadius: 12),
        ],
      ),
    );
  }
}
