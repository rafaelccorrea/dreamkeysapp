import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/services/api_service.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/key_model.dart' as key_models;
import '../services/key_service.dart';

/// Página de criação/edição de chave
class CreateKeyPage extends StatefulWidget {
  final String? keyId;
  
  const CreateKeyPage({super.key, this.keyId});

  @override
  State<CreateKeyPage> createState() => _CreateKeyPageState();
}

class _CreateKeyPageState extends State<CreateKeyPage> {
  final _formKey = GlobalKey<FormState>();
  final KeyService _keyService = KeyService.instance;

  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  // Estados
  key_models.KeyType _selectedType = key_models.KeyType.main;
  key_models.KeyStatus _selectedStatus = key_models.KeyStatus.available;
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  bool _isLoading = false;
  bool _hasProperties = true;

  @override
  void initState() {
    super.initState();
    _checkProperties();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _checkProperties() async {
    try {
      // Verificar se há propriedades disponíveis
      final response = await ApiService.instance.get<dynamic>(
        '/properties?limit=1',
      );

      if (mounted) {
        setState(() {
          if (response.success && response.data != null) {
            if (response.data is List) {
              _hasProperties = (response.data as List).isNotEmpty;
            } else if (response.data is Map<String, dynamic>) {
              final data = response.data as Map<String, dynamic>;
              final properties = data['properties'] as List? ?? 
                                data['data'] as List? ?? [];
              _hasProperties = properties.isNotEmpty;
            } else {
              _hasProperties = false;
            }
          } else {
            _hasProperties = false;
          }
        });

        // Se não houver propriedades, redirecionar
        if (!_hasProperties) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showNoPropertiesDialog();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasProperties = false;
        });
      }
    }
  }

  Future<void> _showNoPropertiesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nenhuma Propriedade Encontrada'),
        content: const Text(
          'Para criar uma chave, é necessário ter pelo menos uma propriedade cadastrada. Deseja criar uma propriedade agora?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              Navigator.pop(context);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Criar Propriedade'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.propertyCreate);
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, selecione uma propriedade'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.keyId != null) {
        // Edição
        final dto = key_models.UpdateKeyDto(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _selectedType.value,
          status: _selectedStatus.value,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );

        final response = await _keyService.updateKey(widget.keyId!, dto);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          if (response.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Chave atualizada com sucesso'),
                backgroundColor: AppColors.status.success,
              ),
            );
            Navigator.of(context).pop(true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao atualizar chave'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
        }
      } else {
        // Criação
        final dto = key_models.CreateKeyDto(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _selectedType.value,
          status: _selectedStatus.value,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          propertyId: _selectedPropertyId!,
        );

        final response = await _keyService.createKey(dto);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          if (response.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Chave criada com sucesso'),
                backgroundColor: AppColors.status.success,
              ),
            );
            Navigator.of(context).pop(true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao criar chave'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
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

    if (!_hasProperties) {
      return AppScaffold(
        title: 'Criar Chave',
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return AppScaffold(
      title: widget.keyId != null ? 'Editar Chave' : 'Criar Chave',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nome
              CustomTextField(
                controller: _nameController,
                label: 'Nome da Chave *',
                hint: 'Ex: Chave Principal',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nome é obrigatório';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Propriedade
              Text(
                'Propriedade *',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
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
              if (_selectedPropertyId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Propriedade é obrigatória',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.status.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              
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
                children: key_models.KeyType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              
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
                children: key_models.KeyStatus.values.map((status) {
                  final isSelected = _selectedStatus == status;
                  return ChoiceChip(
                    label: Text(status.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedStatus = status;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              
              // Localização
              CustomTextField(
                controller: _locationController,
                label: 'Localização',
                hint: 'Ex: Escritório - Gaveta 1',
              ),
              const SizedBox(height: 20),
              
              // Descrição
              CustomTextField(
                controller: _descriptionController,
                label: 'Descrição',
                hint: 'Descrição adicional sobre a chave',
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              
              // Observações
              CustomTextField(
                controller: _notesController,
                label: 'Observações',
                hint: 'Observações gerais',
                maxLines: 3,
              ),
              const SizedBox(height: 32),
              
              // Botões
              Column(
                children: [
                    SizedBox(
                      width: double.infinity,
                      child: CustomButton(
                        text: _isLoading
                            ? (widget.keyId != null ? 'Salvando...' : 'Criando...')
                            : (widget.keyId != null ? 'Salvar Alterações' : 'Criar Chave'),
                        onPressed: _isLoading ? null : _submitForm,
                        icon: _isLoading ? null : (widget.keyId != null ? Icons.save : Icons.add),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

