import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';

/// Página de criação / edição de cliente.
class ClientFormPage extends StatefulWidget {
  final String? clientId;

  const ClientFormPage({super.key, this.clientId});

  @override
  State<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends State<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Identidade
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _phoneController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _rgController = TextEditingController();
  final _birthDateController = TextEditingController();

  // Endereço
  final _zipCodeController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _neighborhoodController = TextEditingController();

  // Profissional
  final _companyNameController = TextEditingController();
  final _jobPositionController = TextEditingController();
  final _contractTypeController = TextEditingController();

  // Financeiro
  final _monthlyIncomeController = TextEditingController();
  final _grossSalaryController = TextEditingController();
  final _netSalaryController = TextEditingController();
  final _familyIncomeController = TextEditingController();
  final _thirteenthSalaryController = TextEditingController();
  final _vacationPayController = TextEditingController();
  final _otherIncomeSourcesController = TextEditingController();
  final _otherIncomeAmountController = TextEditingController();
  final _creditScoreController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAgencyController = TextEditingController();

  // Referências
  final _referenceNameController = TextEditingController();
  final _referencePhoneController = TextEditingController();
  final _referenceRelationshipController = TextEditingController();
  final _professionalReferenceNameController = TextEditingController();
  final _professionalReferencePhoneController = TextEditingController();
  final _professionalReferencePositionController = TextEditingController();

  // Preferências
  final _preferredCityController = TextEditingController();
  final _preferredNeighborhoodController = TextEditingController();
  final _minValueController = TextEditingController();
  final _maxValueController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();

  // Outros
  final _dependentsNotesController = TextEditingController();
  final _mcmvCadunicoNumberController = TextEditingController();
  final _notesController = TextEditingController();

  // Estado
  ClientType _selectedType = ClientType.general;
  ClientStatus _selectedStatus = ClientStatus.active;
  MaritalStatus? _selectedMaritalStatus;
  EmploymentStatus? _selectedEmploymentStatus;
  ClientSource? _leadSource;
  String? _accountType;
  String? _preferredPropertyType;
  String? _mcmvIncomeRange;
  bool? _hasDependents;
  int? _numberOfDependents;
  bool? _isRetired;
  bool? _hasProperty;
  bool? _hasVehicle;
  bool? _mcmvInterested;
  bool? _mcmvEligible;
  int? _minBedrooms;
  int? _maxBedrooms;
  int? _minBathrooms;
  DateTime? _birthDate;

  Client? _client;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    if (widget.clientId != null) _loadClient();
  }

  @override
  void dispose() {
    final controllers = <TextEditingController>[
      _nameController, _emailController, _cpfController, _phoneController,
      _secondaryPhoneController, _whatsappController, _rgController,
      _birthDateController, _zipCodeController, _addressController,
      _cityController, _stateController, _neighborhoodController,
      _companyNameController, _jobPositionController, _contractTypeController,
      _monthlyIncomeController, _grossSalaryController, _netSalaryController,
      _familyIncomeController, _thirteenthSalaryController,
      _vacationPayController, _otherIncomeSourcesController,
      _otherIncomeAmountController, _creditScoreController,
      _bankNameController, _bankAgencyController,
      _referenceNameController, _referencePhoneController,
      _referenceRelationshipController,
      _professionalReferenceNameController,
      _professionalReferencePhoneController,
      _professionalReferencePositionController,
      _preferredCityController, _preferredNeighborhoodController,
      _minValueController, _maxValueController,
      _minAreaController, _maxAreaController,
      _dependentsNotesController, _mcmvCadunicoNumberController,
      _notesController,
    ];
    for (final c in controllers) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ───────────────────────── Loading ─────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final response = await ProfileService.instance.getProfile();
      if (response.success && response.data != null && mounted) {
        setState(() => _currentUserId = response.data!.id);
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
      final response =
          await ClientService.instance.getClientById(widget.clientId!);
      if (!mounted) return;

      if (response.success && response.data != null) {
        final c = response.data!;
        setState(() {
          _client = c;

          _nameController.text = c.name;
          _emailController.text = c.email;
          _cpfController.text = c.cpf;
          _phoneController.text = c.phone;
          _secondaryPhoneController.text = c.secondaryPhone ?? '';
          _whatsappController.text = c.whatsapp ?? '';
          _rgController.text = c.rg ?? '';
          _zipCodeController.text = c.zipCode;
          _addressController.text = c.address;
          _cityController.text = c.city;
          _stateController.text = c.state;
          _neighborhoodController.text = c.neighborhood;
          _notesController.text = c.notes ?? '';

          _selectedType = c.type;
          _selectedStatus = c.status;

          if (c.birthDate != null) {
            try {
              _birthDate = DateTime.parse(c.birthDate!);
              _birthDateController.text =
                  DateFormat('dd/MM/yyyy').format(_birthDate!);
            } catch (e) {
              debugPrint('Erro ao parsear data: $e');
            }
          }

          _companyNameController.text = c.companyName ?? '';
          _jobPositionController.text = c.jobPosition ?? '';
          _contractTypeController.text = c.contractType ?? '';
          _monthlyIncomeController.text = c.monthlyIncome?.toString() ?? '';
          _grossSalaryController.text = c.grossSalary?.toString() ?? '';
          _netSalaryController.text = c.netSalary?.toString() ?? '';
          _thirteenthSalaryController.text =
              c.thirteenthSalary?.toString() ?? '';
          _vacationPayController.text = c.vacationPay?.toString() ?? '';
          _otherIncomeSourcesController.text = c.otherIncomeSources ?? '';
          _otherIncomeAmountController.text =
              c.otherIncomeAmount?.toString() ?? '';
          _familyIncomeController.text = c.familyIncome?.toString() ?? '';
          _creditScoreController.text = c.creditScore?.toString() ?? '';
          _bankNameController.text = c.bankName ?? '';
          _bankAgencyController.text = c.bankAgency ?? '';
          _referenceNameController.text = c.referenceName ?? '';
          _referencePhoneController.text = c.referencePhone ?? '';
          _referenceRelationshipController.text =
              c.referenceRelationship ?? '';
          _professionalReferenceNameController.text =
              c.professionalReferenceName ?? '';
          _professionalReferencePhoneController.text =
              c.professionalReferencePhone ?? '';
          _professionalReferencePositionController.text =
              c.professionalReferencePosition ?? '';
          _dependentsNotesController.text = c.dependentsNotes ?? '';
          _preferredCityController.text = c.preferredCity ?? '';
          _preferredNeighborhoodController.text = c.preferredNeighborhood ?? '';
          _minValueController.text = c.minValue?.toString() ?? '';
          _maxValueController.text = c.maxValue?.toString() ?? '';
          _minAreaController.text = c.minArea?.toString() ?? '';
          _maxAreaController.text = c.maxArea?.toString() ?? '';

          _selectedMaritalStatus = c.maritalStatus;
          _selectedEmploymentStatus = c.employmentStatus;
          _hasDependents = c.hasDependents;
          _numberOfDependents = c.numberOfDependents;
          _isRetired = c.isRetired;
          _hasProperty = c.hasProperty;
          _hasVehicle = c.hasVehicle;
          _accountType = c.accountType;
          _preferredPropertyType = c.preferredPropertyType;
          _minBedrooms = c.minBedrooms;
          _maxBedrooms = c.maxBedrooms;
          _minBathrooms = c.minBathrooms;
          _leadSource = c.leadSource;
          _mcmvInterested = c.mcmvInterested;
          _mcmvEligible = c.mcmvEligible;
          _mcmvIncomeRange = c.mcmvIncomeRange;
          _mcmvCadunicoNumberController.text = c.mcmvCadunicoNumber ?? '';

          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar cliente';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _isLoading = false;
      });
    }
  }

  // ───────────────────────── Save ─────────────────────────

  double? _parseMoney(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    final clean = t.replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.');
    return double.tryParse(clean);
  }

  String? _stringOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      _showSnack('Revise os campos destacados antes de salvar.', error: true);
      return;
    }
    if (_currentUserId == null) {
      _showSnack('Não foi possível identificar o usuário atual.', error: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final dto = CreateClientDto(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        cpf: _cpfController.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        phone: _phoneController.text.trim(),
        zipCode:
            _zipCodeController.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim().toUpperCase(),
        neighborhood: _neighborhoodController.text.trim(),
        type: _selectedType,
        capturedById: _currentUserId!,
        status: _selectedStatus,
        secondaryPhone: _stringOrNull(_secondaryPhoneController.text),
        whatsapp: _stringOrNull(_whatsappController.text),
        birthDate: _birthDate != null
            ? DateFormat('yyyy-MM-dd').format(_birthDate!)
            : null,
        rg: _stringOrNull(_rgController.text),
        maritalStatus: _selectedMaritalStatus,
        hasDependents: _hasDependents,
        numberOfDependents: _numberOfDependents,
        dependentsNotes: _stringOrNull(_dependentsNotesController.text),
        employmentStatus: _selectedEmploymentStatus,
        companyName: _stringOrNull(_companyNameController.text),
        jobPosition: _stringOrNull(_jobPositionController.text),
        contractType: _stringOrNull(_contractTypeController.text),
        isRetired: _isRetired,
        monthlyIncome: _parseMoney(_monthlyIncomeController.text),
        grossSalary: _parseMoney(_grossSalaryController.text),
        netSalary: _parseMoney(_netSalaryController.text),
        thirteenthSalary: _parseMoney(_thirteenthSalaryController.text),
        vacationPay: _parseMoney(_vacationPayController.text),
        otherIncomeSources: _stringOrNull(_otherIncomeSourcesController.text),
        otherIncomeAmount: _parseMoney(_otherIncomeAmountController.text),
        familyIncome: _parseMoney(_familyIncomeController.text),
        creditScore: int.tryParse(_creditScoreController.text.trim()),
        bankName: _stringOrNull(_bankNameController.text),
        bankAgency: _stringOrNull(_bankAgencyController.text),
        accountType: _accountType,
        hasProperty: _hasProperty,
        hasVehicle: _hasVehicle,
        referenceName: _stringOrNull(_referenceNameController.text),
        referencePhone: _stringOrNull(_referencePhoneController.text),
        referenceRelationship:
            _stringOrNull(_referenceRelationshipController.text),
        professionalReferenceName:
            _stringOrNull(_professionalReferenceNameController.text),
        professionalReferencePhone:
            _stringOrNull(_professionalReferencePhoneController.text),
        professionalReferencePosition:
            _stringOrNull(_professionalReferencePositionController.text),
        preferredCity: _stringOrNull(_preferredCityController.text),
        preferredNeighborhood:
            _stringOrNull(_preferredNeighborhoodController.text),
        minValue: _parseMoney(_minValueController.text),
        maxValue: _parseMoney(_maxValueController.text),
        minArea: _parseMoney(_minAreaController.text),
        maxArea: _parseMoney(_maxAreaController.text),
        minBedrooms: _minBedrooms,
        maxBedrooms: _maxBedrooms,
        minBathrooms: _minBathrooms,
        preferredPropertyType: _preferredPropertyType,
        leadSource: _leadSource,
        mcmvInterested: _mcmvInterested,
        mcmvEligible: _mcmvEligible,
        mcmvIncomeRange: _mcmvIncomeRange,
        mcmvCadunicoNumber: _stringOrNull(_mcmvCadunicoNumberController.text),
        notes: _stringOrNull(_notesController.text),
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
                dependentsNotes: dto.dependentsNotes,
                employmentStatus: dto.employmentStatus,
                companyName: dto.companyName,
                jobPosition: dto.jobPosition,
                contractType: dto.contractType,
                isRetired: dto.isRetired,
                monthlyIncome: dto.monthlyIncome,
                grossSalary: dto.grossSalary,
                netSalary: dto.netSalary,
                thirteenthSalary: dto.thirteenthSalary,
                vacationPay: dto.vacationPay,
                otherIncomeSources: dto.otherIncomeSources,
                otherIncomeAmount: dto.otherIncomeAmount,
                familyIncome: dto.familyIncome,
                creditScore: dto.creditScore,
                bankName: dto.bankName,
                bankAgency: dto.bankAgency,
                accountType: dto.accountType,
                hasProperty: dto.hasProperty,
                hasVehicle: dto.hasVehicle,
                referenceName: dto.referenceName,
                referencePhone: dto.referencePhone,
                referenceRelationship: dto.referenceRelationship,
                professionalReferenceName: dto.professionalReferenceName,
                professionalReferencePhone: dto.professionalReferencePhone,
                professionalReferencePosition:
                    dto.professionalReferencePosition,
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
                mcmvCadunicoNumber: dto.mcmvCadunicoNumber,
                notes: dto.notes,
              ),
            );

      if (!mounted) return;
      if (response.success && response.data != null) {
        _showSnack(widget.clientId == null
            ? 'Cliente criado com sucesso!'
            : 'Cliente atualizado com sucesso!');
        Navigator.pop(context, response.data);
      } else {
        _showSnack(
          response.message ??
              'Erro ao ${widget.clientId == null ? 'criar' : 'atualizar'} cliente',
          error: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro: ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
      ),
    );
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.clientId == null ? 'Novo Cliente' : 'Editar Cliente',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _client == null
              ? _buildErrorState(context)
              : _buildForm(context),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 46,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _errorMessage ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroPreview(context),
                  const SizedBox(height: 14),
                  _section(
                    context,
                    icon: Icons.person_outline,
                    title: 'Identificação',
                    description:
                        'Dados básicos do contato — campos obrigatórios estão marcados com *.',
                    initiallyExpanded: true,
                    child: _buildIdentitySection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.category_outlined,
                    title: 'Tipo, status e origem',
                    description:
                        'Como esse cliente está classificado no funil.',
                    initiallyExpanded: true,
                    child: _buildClassificationSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Endereço',
                    description: 'Endereço residencial atual.',
                    initiallyExpanded: true,
                    child: _buildAddressSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.info_outline,
                    title: 'Informações pessoais',
                    description:
                        'Documentos adicionais e composição familiar.',
                    child: _buildPersonalSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.work_outline,
                    title: 'Vida profissional',
                    description: 'Empresa, cargo e tipo de contrato.',
                    child: _buildProfessionalSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Renda e bancos',
                    description:
                        'Capacidade financeira e dados bancários.',
                    child: _buildFinancialSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Preferências imobiliárias',
                    description:
                        'O que esse cliente busca em um imóvel ideal.',
                    child: _buildPreferencesSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.contacts_outlined,
                    title: 'Referências',
                    description: 'Pessoais e profissionais para validação.',
                    child: _buildReferencesSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.home_work_outlined,
                    title: 'MCMV (Minha Casa, Minha Vida)',
                    description: 'Sinalize interesse e elegibilidade.',
                    child: _buildMcmvSection(context),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    icon: Icons.note_alt_outlined,
                    title: 'Observações',
                    description: 'Notas internas livres sobre o cliente.',
                    child: CustomTextField(
                      controller: _notesController,
                      label: 'Notas e observações',
                      prefixIcon: const Icon(Icons.note_outlined),
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildStickyFooter(context),
        ],
      ),
    );
  }

  // ───────────────────────── Hero preview ─────────────────────────

  Widget _buildHeroPreview(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final typeColor = _typeColor(_selectedType);
    final name = _nameController.text.trim();
    final initials = _initials(name);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  typeColor.withValues(alpha: 0.20),
                  typeColor.withValues(alpha: 0.05),
                ]
              : [Colors.white, typeColor.withValues(alpha: 0.10)],
        ),
        border: Border.all(color: typeColor.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 7),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  typeColor.withValues(alpha: 0.85),
                  typeColor.withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: typeColor.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.clientId == null
                      ? 'PRÉ-VISUALIZAÇÃO'
                      : 'EDITANDO CLIENTE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name.isEmpty ? 'Novo cliente' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _previewChip(
                      context,
                      _selectedType.label,
                      typeColor,
                      icon: _iconForType(_selectedType),
                    ),
                    _previewChip(
                      context,
                      _selectedStatus.label,
                      _statusColor(_selectedStatus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewChip(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Sections ─────────────────────────

  Widget _buildIdentitySection(BuildContext context) {
    return Column(
      children: [
        CustomTextField(
          controller: _nameController,
          label: 'Nome completo *',
          prefixIcon: const Icon(Icons.person_outline),
          onChanged: (_) => setState(() {}),
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
        const SizedBox(height: 12),
        CustomTextField(
          controller: _emailController,
          label: 'Email *',
          prefixIcon: const Icon(Icons.email_outlined),
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Email é obrigatório';
            }
            if (!value.contains('@')) return 'Email inválido';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _cpfController,
                label: 'CPF *',
                prefixIcon: const Icon(Icons.fingerprint_rounded),
                keyboardType: TextInputType.number,
                inputFormatters: [CpfInputFormatter()],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'CPF é obrigatório';
                  }
                  final cpf = value.replaceAll(RegExp(r'[^\d]'), '');
                  if (cpf.length != 11) return 'CPF deve ter 11 dígitos';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _rgController,
                label: 'RG',
                prefixIcon: const Icon(Icons.credit_card_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _phoneController,
                label: 'Telefone *',
                prefixIcon: const Icon(Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Telefone é obrigatório';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _whatsappController,
                label: 'WhatsApp',
                prefixIcon: const Icon(Icons.chat_outlined),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _secondaryPhoneController,
          label: 'Telefone secundário',
          prefixIcon: const Icon(Icons.phone_outlined),
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
        ),
        const SizedBox(height: 12),
        _buildDateField(
          context,
          label: 'Data de nascimento',
          controller: _birthDateController,
          icon: Icons.cake_outlined,
          onChanged: (date) => setState(() => _birthDate = date),
          initialDate: _birthDate ??
              DateTime.now().subtract(const Duration(days: 365 * 25)),
        ),
      ],
    );
  }

  Widget _buildClassificationSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Tipo de cliente *'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ClientType.values.map((type) {
            return _ChipSelectable(
              label: type.label,
              selected: _selectedType == type,
              onTap: () => setState(() => _selectedType = type),
              accent: _typeColor(type),
              icon: _iconForType(type),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _fieldLabel(context, 'Status do cliente'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ClientStatus.values.map((status) {
            return _ChipSelectable(
              label: status.label,
              selected: _selectedStatus == status,
              onTap: () => setState(() => _selectedStatus = status),
              accent: _statusColor(status),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _fieldLabel(context, 'Origem do lead'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSelectable(
              label: 'Não informado',
              selected: _leadSource == null,
              onTap: () => setState(() => _leadSource = null),
              accent: accent,
            ),
            ...ClientSource.values.map((src) => _ChipSelectable(
                  label: src.label,
                  selected: _leadSource == src,
                  onTap: () => setState(() => _leadSource = src),
                  accent: accent,
                )),
          ],
        ),
      ],
    );
  }

  Widget _buildAddressSection(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: CustomTextField(
                controller: _zipCodeController,
                label: 'CEP *',
                prefixIcon:
                    const Icon(Icons.markunread_mailbox_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [CepInputFormatter()],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'CEP é obrigatório';
                  }
                  final cep = value.replaceAll(RegExp(r'[^\d]'), '');
                  if (cep.length != 8) return 'CEP deve ter 8 dígitos';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _stateController,
                label: 'UF *',
                prefixIcon: const Icon(Icons.map_outlined),
                maxLength: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'UF';
                  }
                  if (value.trim().length != 2) {
                    return '2 letras';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
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
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
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
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPersonalSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Estado civil'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSelectable(
              label: 'Não informado',
              selected: _selectedMaritalStatus == null,
              onTap: () => setState(() => _selectedMaritalStatus = null),
              accent: accent,
            ),
            ...MaritalStatus.values.map((m) => _ChipSelectable(
                  label: m.label,
                  selected: _selectedMaritalStatus == m,
                  onTap: () => setState(() => _selectedMaritalStatus = m),
                  accent: accent,
                )),
          ],
        ),
        const SizedBox(height: 16),
        _switchTile(
          context,
          icon: Icons.family_restroom_outlined,
          title: 'Possui dependentes',
          subtitle: 'Filhos, agregados ou outros',
          value: _hasDependents ?? false,
          onChanged: (v) => setState(() {
            _hasDependents = v;
            if (!v) _numberOfDependents = null;
          }),
        ),
        if (_hasDependents == true) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _numberOfDependents?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Número de dependentes',
                    prefixIcon: const Icon(Icons.people_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) =>
                      _numberOfDependents = int.tryParse(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _dependentsNotesController,
            label: 'Observações sobre dependentes',
            prefixIcon: const Icon(Icons.notes_outlined),
            maxLines: 2,
          ),
        ],
      ],
    );
  }

  Widget _buildProfessionalSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Situação profissional'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSelectable(
              label: 'Não informado',
              selected: _selectedEmploymentStatus == null,
              onTap: () => setState(() => _selectedEmploymentStatus = null),
              accent: accent,
            ),
            ...EmploymentStatus.values.map((e) => _ChipSelectable(
                  label: e.label,
                  selected: _selectedEmploymentStatus == e,
                  onTap: () =>
                      setState(() => _selectedEmploymentStatus = e),
                  accent: accent,
                )),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _companyNameController,
                label: 'Empresa',
                prefixIcon: const Icon(Icons.business_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _jobPositionController,
                label: 'Cargo',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _contractTypeController,
          label: 'Tipo de contrato',
          prefixIcon: const Icon(Icons.description_outlined),
        ),
        const SizedBox(height: 12),
        _switchTile(
          context,
          icon: Icons.work_off_outlined,
          title: 'Aposentado',
          subtitle: 'Recebe aposentadoria como fonte principal',
          value: _isRetired ?? false,
          onChanged: (v) => setState(() => _isRetired = v),
        ),
      ],
    );
  }

  Widget _buildFinancialSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _monthlyIncomeController,
                label: 'Renda mensal',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _familyIncomeController,
                label: 'Renda familiar',
                prefixIcon: const Icon(Icons.family_restroom_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _grossSalaryController,
                label: 'Salário bruto',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _netSalaryController,
                label: 'Salário líquido',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _thirteenthSalaryController,
                label: '13º Salário',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _vacationPayController,
                label: 'Férias',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _otherIncomeSourcesController,
          label: 'Outras fontes de renda',
          prefixIcon: const Icon(Icons.description_outlined),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _otherIncomeAmountController,
                label: 'Valor outras rendas',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _creditScoreController,
                label: 'Score de crédito',
                prefixIcon: const Icon(Icons.credit_score_outlined),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final score = int.tryParse(value);
                    if (score == null || score < 0 || score > 1000) {
                      return 'Entre 0 e 1000';
                    }
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _bankNameController,
                label: 'Banco',
                prefixIcon: const Icon(Icons.account_balance_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _bankAgencyController,
                label: 'Agência',
                prefixIcon: const Icon(Icons.numbers_rounded),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _fieldLabel(context, 'Tipo de conta'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSelectable(
              label: 'Não informado',
              selected: _accountType == null,
              onTap: () => setState(() => _accountType = null),
              accent: accent,
            ),
            _ChipSelectable(
              label: 'Conta corrente',
              selected: _accountType == 'checking',
              onTap: () => setState(() => _accountType = 'checking'),
              accent: accent,
            ),
            _ChipSelectable(
              label: 'Poupança',
              selected: _accountType == 'savings',
              onTap: () => setState(() => _accountType = 'savings'),
              accent: accent,
            ),
            _ChipSelectable(
              label: 'Salário',
              selected: _accountType == 'salary',
              onTap: () => setState(() => _accountType = 'salary'),
              accent: accent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _switchTile(
          context,
          icon: Icons.house_outlined,
          title: 'Possui imóvel próprio',
          subtitle: 'Patrimônio imobiliário existente',
          value: _hasProperty ?? false,
          onChanged: (v) => setState(() => _hasProperty = v),
        ),
        const SizedBox(height: 8),
        _switchTile(
          context,
          icon: Icons.directions_car_outlined,
          title: 'Possui veículo',
          subtitle: 'Patrimônio automotivo',
          value: _hasVehicle ?? false,
          onChanged: (v) => setState(() => _hasVehicle = v),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _preferredCityController,
                label: 'Cidade preferida',
                prefixIcon: const Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _preferredNeighborhoodController,
                label: 'Bairro preferido',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _minValueController,
                label: 'Valor mínimo',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _maxValueController,
                label: 'Valor máximo',
                prefixIcon: const Icon(Icons.attach_money_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _minAreaController,
                label: 'Área mín. (m²)',
                prefixIcon: const Icon(Icons.square_foot_outlined),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _maxAreaController,
                label: 'Área máx. (m²)',
                prefixIcon: const Icon(Icons.square_foot_outlined),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _fieldLabel(context, 'Quartos'),
        const SizedBox(height: 8),
        _stepperRow(
          context,
          minValue: _minBedrooms,
          maxValue: _maxBedrooms,
          icon: Icons.bed_outlined,
          onChangedMin: (v) => setState(() => _minBedrooms = v),
          onChangedMax: (v) => setState(() => _maxBedrooms = v),
        ),
        const SizedBox(height: 16),
        _fieldLabel(context, 'Banheiros (mínimo)'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSelectable(
              label: 'Indiferente',
              selected: _minBathrooms == null,
              onTap: () => setState(() => _minBathrooms = null),
              accent: accent,
            ),
            for (var i = 1; i <= 6; i++)
              _ChipSelectable(
                label: i == 6 ? '6+' : '$i',
                selected: _minBathrooms == i,
                onTap: () => setState(() => _minBathrooms = i),
                accent: accent,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildReferencesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Referência pessoal',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
        ),
        const SizedBox(height: 10),
        CustomTextField(
          controller: _referenceNameController,
          label: 'Nome',
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _referencePhoneController,
                label: 'Telefone',
                prefixIcon: const Icon(Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _referenceRelationshipController,
                label: 'Relacionamento',
                prefixIcon: const Icon(Icons.favorite_outline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Referência profissional',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
        ),
        const SizedBox(height: 10),
        CustomTextField(
          controller: _professionalReferenceNameController,
          label: 'Nome',
          prefixIcon: const Icon(Icons.business_center_outlined),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                controller: _professionalReferencePhoneController,
                label: 'Telefone',
                prefixIcon: const Icon(Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: _professionalReferencePositionController,
                label: 'Cargo',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMcmvSection(BuildContext context) {
    final accent = _accentColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(
          context,
          icon: Icons.house_siding_outlined,
          title: 'Interessado no MCMV',
          subtitle: 'Habilita campos adicionais do programa',
          value: _mcmvInterested ?? false,
          onChanged: (v) => setState(() {
            _mcmvInterested = v;
            if (!v) {
              _mcmvEligible = null;
              _mcmvIncomeRange = null;
            }
          }),
        ),
        if (_mcmvInterested == true) ...[
          const SizedBox(height: 10),
          _switchTile(
            context,
            icon: Icons.verified_outlined,
            title: 'Elegível para MCMV',
            subtitle: 'Validado pela equipe ou simulação',
            value: _mcmvEligible ?? false,
            onChanged: (v) => setState(() => _mcmvEligible = v),
          ),
          const SizedBox(height: 14),
          _fieldLabel(context, 'Faixa de renda MCMV'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipSelectable(
                label: 'Não informado',
                selected: _mcmvIncomeRange == null,
                onTap: () => setState(() => _mcmvIncomeRange = null),
                accent: accent,
              ),
              _ChipSelectable(
                label: 'Faixa 1',
                selected: _mcmvIncomeRange == 'faixa1',
                onTap: () => setState(() => _mcmvIncomeRange = 'faixa1'),
                accent: accent,
              ),
              _ChipSelectable(
                label: 'Faixa 2',
                selected: _mcmvIncomeRange == 'faixa2',
                onTap: () => setState(() => _mcmvIncomeRange = 'faixa2'),
                accent: accent,
              ),
              _ChipSelectable(
                label: 'Faixa 3',
                selected: _mcmvIncomeRange == 'faixa3',
                onTap: () => setState(() => _mcmvIncomeRange = 'faixa3'),
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          CustomTextField(
            controller: _mcmvCadunicoNumberController,
            label: 'Número CADÚnico',
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }

  // ───────────────────────── Sticky Footer ─────────────────────────

  Widget _buildStickyFooter(BuildContext context) {
    final accent = _accentColor(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _handleSave,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      widget.clientId == null
                          ? Icons.person_add_alt_1
                          : Icons.save_outlined,
                      size: 18,
                    ),
              label: Text(
                _isSaving
                    ? 'Salvando…'
                    : (widget.clientId == null
                        ? 'Criar cliente'
                        : 'Salvar alterações'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Visual helpers ─────────────────────────

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            iconColor: accent,
            collapsedIconColor: ThemeHelpers.textSecondaryColor(context),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: accent.withValues(alpha: 0.10),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
            title: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            children: [child],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? accent.withValues(alpha: 0.08) : Colors.transparent,
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.45)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperRow(
    BuildContext context, {
    required int? minValue,
    required int? maxValue,
    required IconData icon,
    required ValueChanged<int?> onChangedMin,
    required ValueChanged<int?> onChangedMax,
  }) {
    return Row(
      children: [
        Expanded(
          child: _stepperField(
            context,
            label: 'Mínimo',
            value: minValue,
            icon: icon,
            onChanged: onChangedMin,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _stepperField(
            context,
            label: 'Máximo',
            value: maxValue,
            icon: icon,
            onChanged: onChangedMax,
          ),
        ),
      ],
    );
  }

  Widget _stepperField(
    BuildContext context, {
    required String label,
    required int? value,
    required IconData icon,
    required ValueChanged<int?> onChanged,
  }) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final display = value == null ? '—' : value.toString();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  display,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove_rounded,
                color: value == null || value == 0
                    ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.4)
                    : accent),
            onPressed: value == null || value == 0
                ? null
                : () => onChanged(value - 1 == 0 ? null : value - 1),
          ),
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_rounded, color: accent),
            onPressed: () =>
                onChanged((value ?? 0) + 1 > 10 ? 10 : (value ?? 0) + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required ValueChanged<DateTime> onChanged,
    required DateTime initialDate,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: controller.text.isEmpty
            ? const Icon(Icons.calendar_today_outlined)
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  setState(() {
                    controller.clear();
                    _birthDate = null;
                  });
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
          locale: const Locale('pt', 'BR'),
        );
        if (picked != null) {
          controller.text = DateFormat('dd/MM/yyyy').format(picked);
          onChanged(picked);
        }
      },
    );
  }

  // ───────────────────────── Helpers ─────────────────────────

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Color _typeColor(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return const Color(0xFF3B82F6);
      case ClientType.seller:
        return const Color(0xFFF59E0B);
      case ClientType.renter:
        return const Color(0xFF10B981);
      case ClientType.lessor:
        return const Color(0xFF06B6D4);
      case ClientType.investor:
        return const Color(0xFF8B5CF6);
      case ClientType.general:
        return const Color(0xFF64748B);
    }
  }

  IconData _iconForType(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return Icons.shopping_bag_outlined;
      case ClientType.seller:
        return Icons.sell_outlined;
      case ClientType.renter:
        return Icons.home_outlined;
      case ClientType.lessor:
        return Icons.business_outlined;
      case ClientType.investor:
        return Icons.trending_up_outlined;
      case ClientType.general:
        return Icons.person_outline;
    }
  }

  Color _statusColor(ClientStatus status) {
    switch (status) {
      case ClientStatus.active:
        return AppColors.status.success;
      case ClientStatus.inactive:
        return AppColors.status.error;
      case ClientStatus.contacted:
        return AppColors.status.info;
      case ClientStatus.interested:
        return AppColors.status.warning;
      case ClientStatus.closed:
        return Colors.grey;
    }
  }
}

class _ChipSelectable extends StatelessWidget {
  const _ChipSelectable({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    final bg = selected ? accent : ThemeHelpers.cardBackgroundColor(context);
    final border =
        selected ? accent : ThemeHelpers.borderLightColor(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
