import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../services/client_service.dart';
import '../models/client_model.dart';
import 'package:intl/intl.dart';

/// Página de criação/edição de cliente
class ClientFormPage extends StatefulWidget {
  final String? clientId;

  const ClientFormPage({
    super.key,
    this.clientId,
  });

  @override
  State<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends State<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _phoneController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Controllers adicionais
  final _birthDateController = TextEditingController();
  final _anniversaryDateController = TextEditingController();
  final _rgController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _jobPositionController = TextEditingController();
  final _monthlyIncomeController = TextEditingController();
  final _grossSalaryController = TextEditingController();
  final _netSalaryController = TextEditingController();
  final _familyIncomeController = TextEditingController();
  final _creditScoreController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAgencyController = TextEditingController();
  final _referenceNameController = TextEditingController();
  final _referencePhoneController = TextEditingController();
  final _preferredCityController = TextEditingController();
  final _preferredNeighborhoodController = TextEditingController();
  final _minValueController = TextEditingController();
  final _maxValueController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();
  
  // Seleções adicionais
  MaritalStatus? _selectedMaritalStatus;
  EmploymentStatus? _selectedEmploymentStatus;
  bool? _hasDependents;
  int? _numberOfDependents;
  bool? _isRetired;
  bool? _hasProperty;
  bool? _hasVehicle;
  String? _accountType;
  String? _preferredPropertyType;
  int? _minBedrooms;
  int? _maxBedrooms;
  int? _minBathrooms;
  ClientSource? _leadSource;
  bool? _mcmvInterested;
  bool? _mcmvEligible;
  String? _mcmvIncomeRange;
  
  DateTime? _birthDate;
  DateTime? _anniversaryDate;

  Client? _client;
  ClientType _selectedType = ClientType.general;
  ClientStatus _selectedStatus = ClientStatus.active;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    if (widget.clientId != null) {
      _loadClient();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _whatsappController.dispose();
    _zipCodeController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _neighborhoodController.dispose();
    _notesController.dispose();
    _birthDateController.dispose();
    _anniversaryDateController.dispose();
    _rgController.dispose();
    _companyNameController.dispose();
    _jobPositionController.dispose();
    _monthlyIncomeController.dispose();
    _grossSalaryController.dispose();
    _netSalaryController.dispose();
    _familyIncomeController.dispose();
    _creditScoreController.dispose();
    _bankNameController.dispose();
    _bankAgencyController.dispose();
    _referenceNameController.dispose();
    _referencePhoneController.dispose();
    _preferredCityController.dispose();
    _preferredNeighborhoodController.dispose();
    _minValueController.dispose();
    _maxValueController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final response = await ProfileService.instance.getProfile();
      if (response.success && response.data != null) {
        setState(() {
          _currentUserId = response.data!.id;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar ID do usuário: $e');
    }
  }

  Future<void> _loadClient() async {
    if (widget.clientId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ClientService.instance.getClientById(widget.clientId!);

      if (mounted) {
        if (response.success && response.data != null) {
          final client = response.data!;
          setState(() {
            _client = client;
            _nameController.text = client.name;
            _emailController.text = client.email;
            _cpfController.text = client.cpf;
            _phoneController.text = client.phone;
            _secondaryPhoneController.text = client.secondaryPhone ?? '';
            _whatsappController.text = client.whatsapp ?? '';
            _zipCodeController.text = client.zipCode;
            _addressController.text = client.address;
            _cityController.text = client.city;
            _stateController.text = client.state;
            _neighborhoodController.text = client.neighborhood;
            _notesController.text = client.notes ?? '';
            _selectedType = client.type;
            _selectedStatus = client.status;
            
            // Carregar campos adicionais
            if (client.birthDate != null) {
              try {
                _birthDate = DateTime.parse(client.birthDate!);
                _birthDateController.text = DateFormat('dd/MM/yyyy').format(_birthDate!);
              } catch (e) {
                debugPrint('Erro ao parsear data de nascimento: $e');
              }
            }
            if (client.anniversaryDate != null) {
              _anniversaryDateController.text = client.anniversaryDate!;
            }
            _rgController.text = client.rg ?? '';
            _companyNameController.text = client.companyName ?? '';
            _jobPositionController.text = client.jobPosition ?? '';
            _monthlyIncomeController.text = client.monthlyIncome?.toString() ?? '';
            _grossSalaryController.text = client.grossSalary?.toString() ?? '';
            _netSalaryController.text = client.netSalary?.toString() ?? '';
            _familyIncomeController.text = client.familyIncome?.toString() ?? '';
            _creditScoreController.text = client.creditScore?.toString() ?? '';
            _bankNameController.text = client.bankName ?? '';
            _bankAgencyController.text = client.bankAgency ?? '';
            _referenceNameController.text = client.referenceName ?? '';
            _referencePhoneController.text = client.referencePhone ?? '';
            _preferredCityController.text = client.preferredCity ?? '';
            _preferredNeighborhoodController.text = client.preferredNeighborhood ?? '';
            _minValueController.text = client.minValue?.toString() ?? '';
            _maxValueController.text = client.maxValue?.toString() ?? '';
            _minAreaController.text = client.minArea?.toString() ?? '';
            _maxAreaController.text = client.maxArea?.toString() ?? '';
            
            _selectedMaritalStatus = client.maritalStatus;
            _selectedEmploymentStatus = client.employmentStatus;
            _hasDependents = client.hasDependents;
            _numberOfDependents = client.numberOfDependents;
            _isRetired = client.isRetired;
            _hasProperty = client.hasProperty;
            _hasVehicle = client.hasVehicle;
            _accountType = client.accountType;
            _preferredPropertyType = client.preferredPropertyType;
            _minBedrooms = client.minBedrooms;
            _maxBedrooms = client.maxBedrooms;
            _minBathrooms = client.minBathrooms;
            _leadSource = client.leadSource;
            _mcmvInterested = client.mcmvInterested;
            _mcmvEligible = client.mcmvEligible;
            _mcmvIncomeRange = client.mcmvIncomeRange;
            
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar cliente';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro: ID do usuário não encontrado'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final dto = CreateClientDto(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        cpf: _cpfController.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        phone: _phoneController.text.trim(),
        zipCode: _zipCodeController.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim().toUpperCase(),
        neighborhood: _neighborhoodController.text.trim(),
        type: _selectedType,
        capturedById: _currentUserId!,
        status: _selectedStatus,
        secondaryPhone: _secondaryPhoneController.text.trim().isNotEmpty
            ? _secondaryPhoneController.text.trim()
            : null,
        whatsapp: _whatsappController.text.trim().isNotEmpty
            ? _whatsappController.text.trim()
            : null,
        birthDate: _birthDate != null
            ? DateFormat('yyyy-MM-dd').format(_birthDate!)
            : null,
        anniversaryDate: _anniversaryDateController.text.trim().isNotEmpty
            ? _anniversaryDateController.text.trim()
            : null,
        rg: _rgController.text.trim().isNotEmpty
            ? _rgController.text.trim()
            : null,
        maritalStatus: _selectedMaritalStatus,
        hasDependents: _hasDependents,
        numberOfDependents: _numberOfDependents,
        employmentStatus: _selectedEmploymentStatus,
        companyName: _companyNameController.text.trim().isNotEmpty
            ? _companyNameController.text.trim()
            : null,
        jobPosition: _jobPositionController.text.trim().isNotEmpty
            ? _jobPositionController.text.trim()
            : null,
        isRetired: _isRetired,
        monthlyIncome: _monthlyIncomeController.text.trim().isNotEmpty
            ? double.tryParse(_monthlyIncomeController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        grossSalary: _grossSalaryController.text.trim().isNotEmpty
            ? double.tryParse(_grossSalaryController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        netSalary: _netSalaryController.text.trim().isNotEmpty
            ? double.tryParse(_netSalaryController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        familyIncome: _familyIncomeController.text.trim().isNotEmpty
            ? double.tryParse(_familyIncomeController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        creditScore: _creditScoreController.text.trim().isNotEmpty
            ? int.tryParse(_creditScoreController.text.trim())
            : null,
        bankName: _bankNameController.text.trim().isNotEmpty
            ? _bankNameController.text.trim()
            : null,
        bankAgency: _bankAgencyController.text.trim().isNotEmpty
            ? _bankAgencyController.text.trim()
            : null,
        accountType: _accountType,
        hasProperty: _hasProperty,
        hasVehicle: _hasVehicle,
        referenceName: _referenceNameController.text.trim().isNotEmpty
            ? _referenceNameController.text.trim()
            : null,
        referencePhone: _referencePhoneController.text.trim().isNotEmpty
            ? _referencePhoneController.text.trim()
            : null,
        preferredCity: _preferredCityController.text.trim().isNotEmpty
            ? _preferredCityController.text.trim()
            : null,
        preferredNeighborhood: _preferredNeighborhoodController.text.trim().isNotEmpty
            ? _preferredNeighborhoodController.text.trim()
            : null,
        minValue: _minValueController.text.trim().isNotEmpty
            ? double.tryParse(_minValueController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        maxValue: _maxValueController.text.trim().isNotEmpty
            ? double.tryParse(_maxValueController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        minArea: _minAreaController.text.trim().isNotEmpty
            ? double.tryParse(_minAreaController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        maxArea: _maxAreaController.text.trim().isNotEmpty
            ? double.tryParse(_maxAreaController.text.trim().replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'))
            : null,
        minBedrooms: _minBedrooms,
        maxBedrooms: _maxBedrooms,
        minBathrooms: _minBathrooms,
        preferredPropertyType: _preferredPropertyType,
        leadSource: _leadSource,
        mcmvInterested: _mcmvInterested,
        mcmvEligible: _mcmvEligible,
        mcmvIncomeRange: _mcmvIncomeRange,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      final response = widget.clientId == null
          ? await ClientService.instance.createClient(dto)
          : await ClientService.instance.updateClient(
              widget.clientId!,
              UpdateClientDto(
                name: dto.name,
                email: dto.email,
                cpf: dto.cpf,
                phone: dto.phone,
                zipCode: dto.zipCode,
                address: dto.address,
                city: dto.city,
                state: dto.state,
                neighborhood: dto.neighborhood,
                type: dto.type,
                capturedById: dto.capturedById,
                status: dto.status,
                secondaryPhone: dto.secondaryPhone,
                whatsapp: dto.whatsapp,
                birthDate: dto.birthDate,
                anniversaryDate: dto.anniversaryDate,
                rg: dto.rg,
                maritalStatus: dto.maritalStatus,
                hasDependents: dto.hasDependents,
                numberOfDependents: dto.numberOfDependents,
                employmentStatus: dto.employmentStatus,
                companyName: dto.companyName,
                jobPosition: dto.jobPosition,
                isRetired: dto.isRetired,
                monthlyIncome: dto.monthlyIncome,
                grossSalary: dto.grossSalary,
                netSalary: dto.netSalary,
                familyIncome: dto.familyIncome,
                creditScore: dto.creditScore,
                bankName: dto.bankName,
                bankAgency: dto.bankAgency,
                accountType: dto.accountType,
                hasProperty: dto.hasProperty,
                hasVehicle: dto.hasVehicle,
                referenceName: dto.referenceName,
                referencePhone: dto.referencePhone,
                preferredCity: dto.preferredCity,
                preferredNeighborhood: dto.preferredNeighborhood,
                minValue: dto.minValue,
                maxValue: dto.maxValue,
                minArea: dto.minArea,
                maxArea: dto.maxArea,
                minBedrooms: dto.minBedrooms,
                maxBedrooms: dto.maxBedrooms,
                minBathrooms: dto.minBathrooms,
                preferredPropertyType: dto.preferredPropertyType,
                leadSource: dto.leadSource,
                mcmvInterested: dto.mcmvInterested,
                mcmvEligible: dto.mcmvEligible,
                mcmvIncomeRange: dto.mcmvIncomeRange,
                notes: dto.notes,
              ),
            );

      if (mounted) {
        if (response.success && response.data != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.clientId == null
                    ? 'Cliente criado com sucesso!'
                    : 'Cliente atualizado com sucesso!',
              ),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.pop(context, response.data);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ??
                    'Erro ao ${widget.clientId == null ? 'criar' : 'atualizar'} cliente',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: widget.clientId == null ? 'Novo Cliente' : 'Editar Cliente',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _client == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
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
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        CustomButton(
                          text: 'Voltar',
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Informações Básicas
                              _buildSectionTitle(context, theme, 'Informações Básicas'),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _nameController,
                                label: 'Nome Completo *',
                                prefixIcon: const Icon(Icons.person_outline),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Nome é obrigatório';
                                  }
                                  if (value.trim().length < 2) {
                                    return 'Nome deve ter pelo menos 2 caracteres';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _emailController,
                                label: 'Email *',
                                prefixIcon: const Icon(Icons.email_outlined),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Email é obrigatório';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Email inválido';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _cpfController,
                                label: 'CPF *',
                                prefixIcon: const Icon(Icons.badge_outlined),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'CPF é obrigatório';
                                  }
                                  final cpf = value.replaceAll(RegExp(r'[^\d]'), '');
                                  if (cpf.length != 11) {
                                    return 'CPF deve ter 11 dígitos';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _phoneController,
                                label: 'Telefone *',
                                prefixIcon: const Icon(Icons.phone_outlined),
                                keyboardType: TextInputType.phone,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Telefone é obrigatório';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _secondaryPhoneController,
                                label: 'Telefone Secundário',
                                prefixIcon: const Icon(Icons.phone_outlined),
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _whatsappController,
                                label: 'WhatsApp',
                                prefixIcon: const Icon(Icons.chat_outlined),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [PhoneInputFormatter()],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _birthDateController,
                                decoration: InputDecoration(
                                  labelText: 'Data de Nascimento',
                                  prefixIcon: const Icon(Icons.cake_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.calendar_today),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime.now(),
                                        locale: const Locale('pt', 'BR'),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          _birthDate = picked;
                                          _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
                                        });
                                      }
                                    },
                                  ),
                                ),
                                readOnly: true,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                    locale: const Locale('pt', 'BR'),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _birthDate = picked;
                                      _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _rgController,
                                label: 'RG',
                                prefixIcon: const Icon(Icons.badge_outlined),
                                keyboardType: TextInputType.text,
                              ),
                              const SizedBox(height: 32),
                              // Tipo e Status
                              _buildSectionTitle(context, theme, 'Tipo e Status'),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<ClientType>(
                                value: _selectedType,
                                decoration: InputDecoration(
                                  labelText: 'Tipo de Cliente *',
                                  prefixIcon: const Icon(Icons.category_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                items: ClientType.values.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type.label),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedType = value;
                                    });
                                  }
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Tipo é obrigatório';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<ClientStatus>(
                                value: _selectedStatus,
                                decoration: InputDecoration(
                                  labelText: 'Status',
                                  prefixIcon: const Icon(Icons.info_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                items: ClientStatus.values.map((status) {
                                  return DropdownMenuItem(
                                    value: status,
                                    child: Text(status.label),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedStatus = value;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 32),
                              // Endereço
                              _buildSectionTitle(context, theme, 'Endereço'),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _zipCodeController,
                                label: 'CEP *',
                                prefixIcon: const Icon(Icons.markunread_mailbox_outlined),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'CEP é obrigatório';
                                  }
                                  final cep = value.replaceAll(RegExp(r'[^\d]'), '');
                                  if (cep.length != 8) {
                                    return 'CEP deve ter 8 dígitos';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _addressController,
                                label: 'Endereço *',
                                prefixIcon: const Icon(Icons.location_on_outlined),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Endereço é obrigatório';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                    Expanded(
                                    flex: 2,
                                    child: CustomTextField(
                                      controller: _cityController,
                                      label: 'Cidade *',
                                      prefixIcon: const Icon(Icons.location_city_outlined),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Cidade é obrigatória';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _stateController,
                                      decoration: InputDecoration(
                                        labelText: 'UF *',
                                        prefixIcon: const Icon(Icons.map_outlined),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      maxLength: 2,
                                      textCapitalization: TextCapitalization.characters,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'UF é obrigatória';
                                        }
                                        if (value.trim().length != 2) {
                                          return 'UF deve ter 2 caracteres';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _neighborhoodController,
                                label: 'Bairro *',
                                prefixIcon: const Icon(Icons.place_outlined),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Bairro é obrigatório';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 32),
                              // Observações
                              _buildSectionTitle(context, theme, 'Observações'),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _notesController,
                                label: 'Notas e Observações',
                                prefixIcon: const Icon(Icons.note_outlined),
                                maxLines: 4,
                              ),
                              const SizedBox(height: 32),
                              // Informações Adicionais (colapsável)
                              ExpansionTile(
                                title: Text(
                                  'Informações Adicionais',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: ThemeHelpers.textColor(context),
                                  ),
                                ),
                                leading: const Icon(Icons.info_outline),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Você pode adicionar informações adicionais como dados financeiros, preferências imobiliárias e informações profissionais após criar o cliente.',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: ThemeHelpers.textSecondaryColor(context),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Essas informações podem ser editadas na página de detalhes do cliente.',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: ThemeHelpers.textSecondaryColor(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                      // Botões de ação
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: ThemeHelpers.cardBackgroundColor(context),
                          border: Border(
                            top: BorderSide(
                              color: ThemeHelpers.borderLightColor(context),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isSaving ? null : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: CustomButton(
                                text: widget.clientId == null ? 'Criar Cliente' : 'Salvar Alterações',
                                icon: _isSaving ? null : Icons.save,
                                onPressed: _isSaving ? null : _handleSave,
                                isLoading: _isSaving,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: ThemeHelpers.textColor(context),
      ),
    );
  }
}

