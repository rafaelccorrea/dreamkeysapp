import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../utils/client_phone_rules.dart';
import '../widgets/client_date_field.dart';
import '../widgets/client_form_kit.dart';
import '../widgets/spouse_form.dart';

/// Características desejadas — mesmas chaves e rótulos do
/// `DesiredFeaturesInput` do web (`types/match.ts › DesiredFeatures`).
const List<(String, String, IconData)> _kDesiredFeatures = [
  ('hasGarage', 'Garagem', Icons.garage_outlined),
  ('hasPool', 'Piscina', Icons.pool_outlined),
  ('hasGarden', 'Jardim', Icons.yard_outlined),
  ('hasBalcony', 'Varanda', Icons.balcony_outlined),
  ('hasGrill', 'Churrasqueira', Icons.outdoor_grill_outlined),
  ('hasElevator', 'Elevador', Icons.elevator_outlined),
  ('isFurnished', 'Mobiliado', Icons.chair_outlined),
  ('petsAllowed', 'Aceita Pets', Icons.pets_outlined),
  ('hasAirConditioning', 'Ar Condicionado', Icons.ac_unit_outlined),
  ('hasGatedCommunity', 'Condomínio Fechado', Icons.fence_outlined),
  ('hasSportsArea', 'Área de Esportes', Icons.sports_soccer_outlined),
  ('hasPartyRoom', 'Salão de Festas', Icons.celebration_outlined),
  ('hasPlayground', 'Playground', Icons.toys_outlined),
  ('hasSecurity', 'Segurança 24h', Icons.security_outlined),
];

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

  /// Alvo da rolagem quando a pendência é a situação profissional.
  final _professionalSectionKey = GlobalKey();

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

  // Características desejadas ("Outras características", separadas por vírgula)
  final _otherFeaturesController = TextEditingController();
  Map<String, dynamic> _desiredFeatures = {};

  // Vida profissional (datas) e crédito — paridade com o web
  DateTime? _jobStartDate;
  DateTime? _jobEndDate;
  bool _isCurrentlyWorking = true;
  DateTime? _lastCreditCheck;

  // Captador: o do cadastro; só na falta dele usa o usuário atual (web).
  String? _capturedById;
  List<UserInfo> _users = [];
  bool _loadingUsers = false;

  // Cônjuge (seção aparece na edição, com Casado(a) ou União Estável)
  Spouse? _spouse;

  /// Regra do web: havendo renda, exigir situação profissional ou aposentado.
  String? _employmentError;

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
  // Sem o código HTTP a tela não sabe se foi permissão, sessão ou queda.
  int _errorStatus = 0;
  Object? _errorRaw;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _loadUsers();
    if (widget.clientId != null) _loadClient();
  }

  bool get _hasFormPermission => ModuleAccessService.instance.hasPermission(
        widget.clientId == null ? 'client:create' : 'client:update',
      );

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    final response = await ClientService.instance.getCompanyUsers();
    if (!mounted) return;
    setState(() {
      _loadingUsers = false;
      if (response.success && response.data != null) {
        _users = response.data!;
      }
    });
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
      _notesController, _otherFeaturesController,
    ];
    for (final c in controllers) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ───────────────────────── Loading ─────────────────────────

  Future<void> _loadCurrentUserId() async {
    try {
      final response = await ProfileService.instance.getProfile();
      if (response.success && response.data != null && mounted) {
        setState(() {
          _currentUserId = response.data!.id;
          // Novo cadastro: captador padrão = usuário atual. Na edição o
          // `_loadClient` sobrescreve com o captador gravado.
          _capturedById ??= response.data!.id;
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
      _errorStatus = 0;
      _errorRaw = null;
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
          _cpfController.text =
              c.cpf.trim().isEmpty ? '' : Masks.cpf(c.cpf);
          _phoneController.text = ClientPhoneRules.maskAuto(c.phone);
          _secondaryPhoneController.text =
              ClientPhoneRules.maskAuto(c.secondaryPhone);
          _whatsappController.text = ClientPhoneRules.maskAuto(c.whatsapp);
          _rgController.text = c.rg ?? '';
          _zipCodeController.text =
              c.zipCode.trim().isEmpty ? '' : Masks.cep(c.zipCode);
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
          // Dinheiro já no formato da máscara do campo ('3.500,00'): com
          // '3500.0' cru, apagar um dígito virava '35,00'.
          _monthlyIncomeController.text = _moneyText(c.monthlyIncome);
          _grossSalaryController.text = _moneyText(c.grossSalary);
          _netSalaryController.text = _moneyText(c.netSalary);
          _thirteenthSalaryController.text = _moneyText(c.thirteenthSalary);
          _vacationPayController.text = _moneyText(c.vacationPay);
          _otherIncomeSourcesController.text = c.otherIncomeSources ?? '';
          _otherIncomeAmountController.text =
              _moneyText(c.otherIncomeAmount);
          _familyIncomeController.text = _moneyText(c.familyIncome);
          _jobStartDate = _parseDate(c.jobStartDate);
          _jobEndDate = _parseDate(c.jobEndDate);
          _isCurrentlyWorking = c.isCurrentlyWorking ?? true;
          _lastCreditCheck = _parseDate(c.lastCreditCheck);
          _desiredFeatures = Map<String, dynamic>.from(
            c.desiredFeatures ?? const <String, dynamic>{},
          );
          final other = _desiredFeatures['other'];
          _otherFeaturesController.text =
              other is List ? other.map((e) => e.toString()).join(', ') : '';
          _spouse = c.spouse;
          final captured = c.capturedById?.trim() ?? '';
          _capturedById = captured.isNotEmpty
              ? captured
              : (_currentUserId ?? _capturedById);
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
          _minValueController.text = _moneyText(c.minValue);
          _maxValueController.text = _moneyText(c.maxValue);
          _minAreaController.text = _numberText(c.minArea);
          _maxAreaController.text = _numberText(c.maxArea);

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
          _errorStatus = response.statusCode;
          _errorRaw = response.error;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _errorStatus = 0;
        _errorRaw = e;
        _isLoading = false;
      });
    }
  }

  // ───────────────────────── Save ─────────────────────────

  String _moneyText(double? value) {
    if (value == null) return '';
    // Máscara padrão de dinheiro (`1.234,56`; o "R$ " é prefixo do campo),
    // arredondada em centavos como antes.
    return CurrencyInputFormatter.format((value * 100).round() / 100);
  }

  String _numberText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  String? _formatDate(DateTime? value) =>
      value == null ? null : DateFormat('yyyy-MM-dd').format(value);

  double? _parseMoney(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    final clean = t.replaceAll(RegExp(r'[^\d,.]'), '').replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean);
  }

  double? _parseNumber(String value) {
    final t = value.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Qualquer renda informada (mensal, familiar, bruta, líquida ou outras) —
  /// mesmo gatilho do `validateForm` do web.
  bool get _hasAnyIncome {
    for (final c in [
      _monthlyIncomeController,
      _familyIncomeController,
      _grossSalaryController,
      _netSalaryController,
      _otherIncomeAmountController,
    ]) {
      final v = _parseMoney(c.text);
      if (v != null && v > 0) return true;
    }
    return false;
  }

  String? _phoneDuplicateError(String field) {
    final errors = ClientPhoneRules.duplicateErrors(
      ClientPhoneRules.contactEntries(
        phone: _phoneController.text,
        secondaryPhone: _secondaryPhoneController.text,
        whatsapp: _whatsappController.text,
      ),
    );
    return errors[field];
  }

  Map<String, dynamic>? _desiredFeaturesPayload() {
    final out = <String, dynamic>{};
    _desiredFeatures.forEach((key, value) {
      if (key == 'other' || key == 'garageSpots') return;
      if (value == true) out[key] = true;
    });
    final spots = _desiredFeatures['garageSpots'];
    if (out['hasGarage'] == true && spots is int && spots > 0) {
      out['garageSpots'] = spots;
    }
    final other = _otherFeaturesController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (other.isNotEmpty) out['other'] = other;
    return out.isEmpty ? null : out;
  }

  String? _stringOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _handleSave() async {
    // Situação profissional não é campo de texto: a regra roda à parte.
    final employmentError = _hasAnyIncome &&
            _selectedEmploymentStatus == null &&
            _isRetired != true
        ? 'Informe a situação profissional ou marque que é aposentado(a)'
        : null;
    setState(() => _employmentError = employmentError);
    final fieldsOk = _formKey.currentState!.validate();
    if (!fieldsOk || employmentError != null) {
      _showSnack('Revise os campos destacados antes de salvar.', error: true);
      _revealFirstError();
      return;
    }
    final capturedBy = (_capturedById?.trim().isNotEmpty ?? false)
        ? _capturedById!.trim()
        : _currentUserId;
    if (capturedBy == null || capturedBy.isEmpty) {
      _showSnack('Selecione o captador do cliente.', error: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final dto = CreateClientDto(
        name: _nameController.text.trim(),
        email: _stringOrNull(_emailController.text),
        cpf: _stringOrNull(
          _cpfController.text.replaceAll(RegExp(r'[^\d]'), ''),
        ),
        phone: _phoneController.text.trim(),
        zipCode: _stringOrNull(
          _zipCodeController.text.replaceAll(RegExp(r'[^\d]'), ''),
        ),
        address: _stringOrNull(_addressController.text),
        city: _stringOrNull(_cityController.text),
        state: _stringOrNull(_stateController.text)?.toUpperCase(),
        neighborhood: _stringOrNull(_neighborhoodController.text),
        type: _selectedType,
        capturedById: capturedBy,
        status: _selectedStatus,
        jobStartDate: _formatDate(_jobStartDate),
        jobEndDate: _isCurrentlyWorking ? null : _formatDate(_jobEndDate),
        isCurrentlyWorking: _isCurrentlyWorking,
        lastCreditCheck: _formatDate(_lastCreditCheck),
        desiredFeatures: _desiredFeaturesPayload(),
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
        minArea: _parseNumber(_minAreaController.text),
        maxArea: _parseNumber(_maxAreaController.text),
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
                jobStartDate: dto.jobStartDate,
                jobEndDate: dto.jobEndDate,
                isCurrentlyWorking: dto.isCurrentlyWorking,
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
                lastCreditCheck: dto.lastCreditCheck,
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
                desiredFeatures: dto.desiredFeatures,
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
      final cause = ErrorCause.fromException(e);
      _showSnack('${cause.title}. ${cause.cause}', error: true);
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

  bool get _isEdit => widget.clientId != null;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.clientId == null ? 'Novo Cliente' : 'Editar Cliente',
      // Formulário com barra de salvar fixa: sem a navegação de baixo (mesmo
      // padrão da ficha de venda, da locação e das metas).
      showBottomNavigation: false,
      body: !_hasFormPermission
          ? AppErrorState.fromApi(
              message: widget.clientId == null
                  ? 'Você não tem permissão para cadastrar clientes.'
                  : 'Você não tem permissão para editar clientes.',
              statusCode: 403,
              secondaryLabel: 'Voltar',
              onSecondary: () => Navigator.pop(context),
            )
          : _isLoading
              ? _buildLoadingSkeleton(context)
              : _errorMessage != null && _client == null
                  ? _buildErrorState(context)
                  : _buildForm(context),
    );
  }

  /// Esqueleto fiel ao formulário: prévia, faixa dos obrigatórios, bloco
  /// principal (nome, telefones, captador) e as linhas das seções.
  Widget _buildLoadingSkeleton(BuildContext context) {
    Widget sectionRow() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              SkeletonBox(width: 36, height: 36, borderRadius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 150, height: 13),
                    SizedBox(height: 6),
                    SkeletonText(width: 210, height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
    const field = SkeletonBox(height: 50, borderRadius: 14);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Row(
          children: [
            SkeletonBox(width: 56, height: 56, borderRadius: 28),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 180, height: 18),
                  SizedBox(height: 8),
                  SkeletonText(width: 130, height: 12),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SkeletonBox(height: 40, borderRadius: 12),
        const SizedBox(height: 6),
        sectionRow(),
        field,
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(child: field),
            SizedBox(width: 12),
            Expanded(child: field),
          ],
        ),
        const SizedBox(height: 12),
        field,
        const SizedBox(height: 18),
        for (var i = 0; i < 5; i++) sectionRow(),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
      error: _errorRaw,
      onRetry: _loadClient,
      secondaryLabel: 'Voltar',
      onSecondary: () => Navigator.pop(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final sections = _buildSections(context);
    Widget scrollArea({required bool inlineActions}) => Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              // Folga no fim: o botão flutuante do chat (quando há mensagens
              // não lidas) não cobre o último campo.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...sections,
                      if (inlineActions) ...[
                        const SizedBox(height: 8),
                        _buildActionBar(context, framed: false),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    final regular = scrollArea(inlineActions: false);
    final compact = scrollArea(inlineActions: true);
    final footer = _buildActionBar(context, framed: true);

    return Theme(
      data: clientFormTheme(context),
      child: Form(
        key: _formKey,
        // Tela baixa (paisagem, teclado aberto): a barra fixa espremeria o
        // formulário até sumir — os botões descem para o fim da rolagem.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cramped = constraints.maxHeight < 260;
            return Column(
              children: cramped ? [compact] : [regular, footer],
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, {required bool framed}) {
    return ClientFormActionBar(
      confirmLabel: _isEdit ? 'Salvar alterações' : 'Criar cliente',
      confirmIcon:
          _isEdit ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
      // Salvar = verde de confirmação; criar = marca (CTA principal).
      confirmColor:
          _isEdit ? clientFormSuccess(context) : clientFormAccent(context),
      onConfirm: _handleSave,
      onCancel: () => Navigator.pop(context),
      busy: _isSaving,
      framed: framed,
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    final isEdit = _isEdit;
    return [
      _buildHero(context),
      const SizedBox(height: 6),
      ClientFormSection(
        key: const ValueKey('client-form-essential'),
        icon: isEdit ? Icons.person_outline : Icons.bolt_rounded,
        title: isEdit ? 'Dados principais' : 'Cadastro rápido',
        description: isEdit
            ? 'Nome e telefone são obrigatórios.'
            : 'Nome e telefone bastam para salvar; o captador já vem com você.',
        collapsible: false,
        showDivider: false,
        badge: 'Obrigatório',
        child: _buildEssentialSection(context),
      ),
      const ClientFormBand(
        'Dados opcionais',
        icon: Icons.playlist_add_rounded,
        topSpacing: 4,
      ),
      ClientFormSection(
        key: const ValueKey('client-form-classification'),
        icon: Icons.category_outlined,
        title: 'Classificação',
        description: 'Tipo, status e origem do lead.',
        initiallyExpanded: true,
        showDivider: false,
        summary: _classificationSummary,
        child: _buildClassificationSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-contact'),
        icon: Icons.badge_outlined,
        title: 'Contato e documentos',
        description: 'E-mail, CPF, RG, outro telefone e nascimento.',
        initiallyExpanded: isEdit,
        summary: _contactSummary,
        child: _buildContactSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-address'),
        icon: Icons.location_on_outlined,
        title: 'Endereço',
        description: 'Onde o cliente mora hoje.',
        initiallyExpanded: isEdit,
        summary: _addressSummary,
        child: _buildAddressSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-family'),
        icon: Icons.family_restroom_outlined,
        title: 'Família',
        description: 'Estado civil e dependentes.',
        summary: _personalSummary,
        child: _buildPersonalSection(context),
      ),
      if (_client != null && _showsSpouse)
        ClientFormSection(
          key: const ValueKey('client-form-spouse'),
          icon: Icons.people_outline,
          title: 'Cônjuge',
          description: 'Vinculado ao cliente e usado nas fichas.',
          initiallyExpanded: true,
          summary: _spouseSummary,
          child: _buildSpouseSection(context),
        ),
      ClientFormSection(
        key: _professionalSectionKey,
        icon: Icons.work_outline,
        title: 'Vida profissional',
        description: 'Situação, empresa, cargo e contrato.',
        forceExpanded: _employmentError != null,
        summary: _professionalSummary,
        child: _buildProfessionalSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-income'),
        icon: Icons.account_balance_wallet_outlined,
        title: 'Renda e bancos',
        description: 'Renda, crédito, banco e patrimônio.',
        summary: _financialSummary,
        child: _buildFinancialSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-preferences'),
        icon: Icons.tune_rounded,
        title: 'Preferências do imóvel',
        description: 'Região, faixa de valor, área e cômodos que procura.',
        summary: _preferencesSummary,
        child: _buildPreferencesSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-features'),
        icon: Icons.star_outline_rounded,
        title: 'Características desejadas',
        description: 'Comodidades e diferenciais que o cliente quer.',
        summary: _featuresSummary,
        child: _buildDesiredFeaturesSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-references'),
        icon: Icons.contacts_outlined,
        title: 'Referências',
        description: 'Uma pessoal e uma profissional, para validação.',
        summary: _referencesSummary,
        child: _buildReferencesSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-mcmv'),
        icon: Icons.home_work_outlined,
        title: 'Minha Casa, Minha Vida',
        description: 'Interesse, elegibilidade e faixa do programa.',
        summary: _mcmvSummary,
        child: _buildMcmvSection(context),
      ),
      ClientFormSection(
        key: const ValueKey('client-form-notes'),
        icon: Icons.note_alt_outlined,
        title: 'Observações',
        description: 'Anotações internas livres sobre o cliente.',
        summary: _notesSummary,
        child: ClientFormField(
          controller: _notesController,
          label: 'Observações',
          hint: 'Preferências, melhor horário, histórico do atendimento…',
          maxLines: 4,
        ),
      ),
    ];
  }

  // ───────────────────────── Resumos das seções ─────────────────────────

  bool _has(TextEditingController c) => c.text.trim().isNotEmpty;

  String _joinPt(List<String> parts) {
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} e ${parts.last}';
  }

  /// "Com e-mail, CPF e RG" — o que já foi preenchido numa seção fechada.
  ClientSectionSummary? _filledSummary(Map<String, bool> items) {
    final names = [
      for (final entry in items.entries)
        if (entry.value) entry.key,
    ];
    if (names.isEmpty) return null;
    return ClientSectionSummary('Com ${_joinPt(names)}');
  }

  ClientSectionSummary? _classificationSummary() {
    final parts = <String>[
      _selectedType.label,
      _selectedStatus.label,
      if (_leadSource != null) 'via ${_leadSource!.label}',
    ];
    return ClientSectionSummary(parts.join(' · '));
  }

  ClientSectionSummary? _contactSummary() => _filledSummary({
        'e-mail': _has(_emailController),
        'CPF': _has(_cpfController),
        'RG': _has(_rgController),
        'outro telefone': _has(_secondaryPhoneController),
        'nascimento': _birthDate != null,
      });

  ClientSectionSummary? _addressSummary() {
    final place = [
      _neighborhoodController.text.trim(),
      _cityController.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final uf = _stateController.text.trim().toUpperCase();
    if (place.isNotEmpty || uf.isNotEmpty) {
      return ClientSectionSummary(
        [place, uf].where((e) => e.isNotEmpty).join(' – '),
      );
    }
    return _filledSummary({
      'CEP': _has(_zipCodeController),
      'endereço': _has(_addressController),
    });
  }

  ClientSectionSummary? _personalSummary() {
    final dependents = _numberOfDependents ?? 0;
    final parts = <String>[
      if (_selectedMaritalStatus != null) _selectedMaritalStatus!.label,
      if (_hasDependents == true)
        dependents > 1
            ? '$dependents dependentes'
            : (dependents == 1 ? '1 dependente' : 'Com dependentes'),
    ];
    if (parts.isEmpty) return null;
    return ClientSectionSummary(parts.join(' · '));
  }

  ClientSectionSummary? _spouseSummary() {
    final spouse = _spouse;
    return spouse == null ? null : ClientSectionSummary(spouse.name);
  }

  ClientSectionSummary? _professionalSummary() {
    final error = _employmentError;
    if (error != null) return ClientSectionSummary.error(error);
    final parts = <String>[
      if (_selectedEmploymentStatus != null) _selectedEmploymentStatus!.label,
      if (_has(_companyNameController)) _companyNameController.text.trim(),
      if (_has(_jobPositionController)) _jobPositionController.text.trim(),
      if (_isRetired == true &&
          _selectedEmploymentStatus != EmploymentStatus.retired)
        'Aposentado(a)',
    ];
    if (parts.isEmpty) return null;
    return ClientSectionSummary(parts.join(' · '));
  }

  ClientSectionSummary? _financialSummary() {
    final income = _monthlyIncomeController.text.trim();
    if (income.isNotEmpty) {
      return ClientSectionSummary('Renda mensal R\$ $income');
    }
    return _filledSummary({
      'renda familiar': _has(_familyIncomeController),
      'salário': _has(_grossSalaryController) ||
          _has(_netSalaryController) ||
          _has(_thirteenthSalaryController) ||
          _has(_vacationPayController),
      'outras rendas': _has(_otherIncomeSourcesController) ||
          _has(_otherIncomeAmountController),
      'crédito': _has(_creditScoreController) || _lastCreditCheck != null,
      'banco': _has(_bankNameController) ||
          _has(_bankAgencyController) ||
          _accountType != null,
      'patrimônio': _hasProperty == true || _hasVehicle == true,
    });
  }

  ClientSectionSummary? _preferencesSummary() => _filledSummary({
        'região': _has(_preferredCityController) ||
            _has(_preferredNeighborhoodController),
        'faixa de valor':
            _has(_minValueController) || _has(_maxValueController),
        'área': _has(_minAreaController) || _has(_maxAreaController),
        'quartos': _minBedrooms != null || _maxBedrooms != null,
        'banheiros': _minBathrooms != null,
      });

  ClientSectionSummary? _featuresSummary() {
    final selected = [
      for (final f in _kDesiredFeatures)
        if (_desiredFeatures[f.$1] == true) f.$2,
    ];
    final hasOther = _has(_otherFeaturesController);
    if (selected.isEmpty) {
      return hasOther
          ? const ClientSectionSummary('Com outras características')
          : null;
    }
    final extra = (selected.length > 3 ? selected.length - 3 : 0) +
        (hasOther ? 1 : 0);
    final shown = selected.take(3).join(', ');
    return ClientSectionSummary(extra > 0 ? '$shown e mais $extra' : shown);
  }

  ClientSectionSummary? _referencesSummary() {
    final parts = <String>[
      if (_has(_referenceNameController))
        'Pessoal: ${_referenceNameController.text.trim()}',
      if (_has(_professionalReferenceNameController))
        'Profissional: ${_professionalReferenceNameController.text.trim()}',
    ];
    if (parts.isNotEmpty) return ClientSectionSummary(parts.join(' · '));
    return _filledSummary({
      'telefone de referência': _has(_referencePhoneController) ||
          _has(_professionalReferencePhoneController),
    });
  }

  ClientSectionSummary? _mcmvSummary() {
    if (_mcmvInterested != true) return null;
    final range = switch (_mcmvIncomeRange) {
      'faixa1' => 'Faixa 1',
      'faixa2' => 'Faixa 2',
      'faixa3' => 'Faixa 3',
      _ => null,
    };
    final parts = <String>[
      'Interessado',
      if (_mcmvEligible == true) 'elegível',
      if (range != null) range,
    ];
    return ClientSectionSummary(parts.join(' · '));
  }

  ClientSectionSummary? _notesSummary() {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return null;
    return ClientSectionSummary(notes.split('\n').first);
  }

  // ───────────────────────── Prévia ─────────────────────────

  /// Prévia viva do cliente + os dois obrigatórios marcando conforme o
  /// corretor digita (só nome e telefone redesenham, não a tela inteira).
  Widget _buildHero(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_nameController, _phoneController]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final muted = ThemeHelpers.textSecondaryColor(context);
        final typeColor = _typeColor(context, _selectedType);
        final name = _nameController.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: typeColor.withValues(alpha: isDark ? 0.22 : 0.14),
                    border: Border.all(
                      color: typeColor.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: name.isEmpty
                      ? Icon(
                          _iconForType(_selectedType),
                          color: typeColor,
                          size: 24,
                        )
                      : Text(
                          _initialsOf(name),
                          maxLines: 1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty
                            ? name
                            : (_isEdit ? 'Cliente sem nome' : 'Novo cliente'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.15,
                          color: name.isEmpty
                              ? muted
                              : ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _heroTag(
                            context,
                            _selectedType.label,
                            typeColor,
                            icon: _iconForType(_selectedType),
                          ),
                          _heroTag(
                            context,
                            _selectedStatus.label,
                            _statusColor(context, _selectedStatus),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildRequirementStrip(context),
          ],
        );
      },
    );
  }

  Widget _heroTag(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Os dois obrigatórios à vista: marcam em verde assim que ficam válidos
  /// (mesma régua dos validadores: nome com 3+ letras, telefone com DDD).
  Widget _buildRequirementStrip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final success = clientFormSuccess(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final nameOk = _nameController.text.trim().length >= 3;
    final phoneOk = ClientPhoneRules.isValidPhone(_phoneController.text);
    final done = nameOk && phoneOk;

    Widget mark(String label, bool ok) => Semantics(
          label: ok ? '$label preenchido' : '$label pendente',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: ok ? success : muted,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ok ? ThemeHelpers.textColor(context) : muted,
                  ),
                ),
              ],
            ),
          ),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: done
            ? success.withValues(alpha: isDark ? 0.14 : 0.08)
            : (isDark
                ? AppColors.background.backgroundSecondaryDarkMode
                : AppColors.background.backgroundSecondary),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? success.withValues(alpha: 0.45)
              : ThemeHelpers.borderLightColor(context),
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          mark('Nome', nameOk),
          mark('Telefone', phoneOk),
          Text(
            done
                ? 'Obrigatórios preenchidos'
                : 'Só estes dois são obrigatórios',
            style: theme.textTheme.bodySmall?.copyWith(
              color: done ? ThemeHelpers.textColor(context) : muted,
              fontWeight: done ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Sections ─────────────────────────

  /// Nome, telefones e captador — o que o corretor preenche em segundos.
  Widget _buildEssentialSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientFormField(
          controller: _nameController,
          label: 'Nome completo',
          isRequired: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Nome é obrigatório';
            // O back valida @Length(3, 255).
            if (v.length < 3) return 'Nome deve ter pelo menos 3 caracteres';
            if (v.length > 255) {
              return 'Nome não pode ter mais que 255 caracteres';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: ClientFormField(
            controller: _phoneController,
            label: 'Telefone',
            isRequired: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            textInputAction: TextInputAction.next,
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Telefone é obrigatório';
              if (!ClientPhoneRules.isValidPhone(v)) {
                return 'Telefone inválido: informe DDD + número';
              }
              return _phoneDuplicateError('phone');
            },
          ),
          right: ClientFormField(
            controller: _whatsappController,
            label: 'WhatsApp',
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            textInputAction: TextInputAction.done,
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null;
              if (!ClientPhoneRules.isValidPhone(v)) {
                return 'WhatsApp inválido: informe DDD + número';
              }
              return _phoneDuplicateError('whatsapp');
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildCapturedByField(context),
      ],
    );
  }

  Widget _buildClassificationSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormCaption('Tipo de cliente'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in ClientType.values)
              ClientChoiceChip(
                label: type.label,
                icon: _iconForType(type),
                color: _typeColor(context, type),
                selected: _selectedType == type,
                onTap: () => setState(() => _selectedType = type),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const ClientFormCaption('Status'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in ClientStatus.values)
              ClientChoiceChip(
                label: status.label,
                color: _statusColor(context, status),
                selected: _selectedStatus == status,
                onTap: () => setState(() => _selectedStatus = status),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const ClientFormCaption(
          'Origem do lead',
          hint: 'Por onde o cliente chegou até você.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ClientChoiceChip(
              label: 'Não informado',
              color: neutral,
              selected: _leadSource == null,
              onTap: () => setState(() => _leadSource = null),
            ),
            for (final source in ClientSource.values)
              ClientChoiceChip(
                label: source.label,
                selected: _leadSource == source,
                onTap: () => setState(() => _leadSource = source),
              ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────── Captador ─────────────────────────

  UserInfo? get _selectedCapturer {
    final id = _capturedById;
    if (id == null || id.isEmpty) return null;
    for (final u in _users) {
      if (u.id == id) return u;
    }
    final captured = _client?.capturedBy;
    if (captured != null && captured.id == id) return captured;
    return null;
  }

  /// Select com o desenho dos campos — o `FieldSelect` "Captador" do web.
  /// Já nasce com o usuário atual; a inicial de quem captou fica à vista.
  Widget _buildCapturedByField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final selected = _selectedCapturer;
    final id = _capturedById ?? '';
    final isMe = id.isNotEmpty && id == _currentUserId;
    String? value;
    if (selected != null) {
      value = isMe ? '${selected.name} (você)' : selected.name;
    } else if (id.isNotEmpty) {
      value = isMe ? 'Você' : 'Captador selecionado';
    }
    final initials = selected != null ? _initialsOf(selected.name) : null;
    return InkWell(
      onTap: _openCapturedByPicker,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          label: const ClientFieldLabel('Captador'),
          hintText: _loadingUsers
              ? 'Carregando usuários…'
              : 'Selecione o captador',
          helperText: _isEdit
              ? 'Quem trouxe este cliente.'
              : 'Quem trouxe este cliente — vem com você por padrão.',
          helperMaxLines: 2,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
              ),
              child: initials != null
                  ? Text(
                      initials,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    )
                  : Icon(Icons.person_pin_outlined, size: 16, color: accent),
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
        ),
        child: Text(
          value ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }

  Future<void> _openCapturedByPicker() async {
    FocusScope.of(context).unfocus();
    if (_users.isEmpty && !_loadingUsers) await _loadUsers();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CapturerPickerSheet(
        users: _users,
        selectedId: _capturedById,
        currentUserId: _currentUserId,
        onReload: () async {
          await _loadUsers();
          return _users;
        },
      ),
    );
    if (picked != null && mounted) setState(() => _capturedById = picked);
  }

  /// E-mail, documentos, outro telefone e nascimento — tudo opcional; o
  /// formato só é conferido quando o campo vem preenchido.
  Widget _buildContactSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientFormField(
          controller: _emailController,
          label: 'E-mail',
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return null;
            if (!ClientPhoneRules.isValidEmail(v)) return 'E-mail inválido';
            if (v.length > 255) {
              return 'E-mail não pode ter mais que 255 caracteres';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 140,
          left: ClientFormField(
            controller: _cpfController,
            label: 'CPF',
            keyboardType: TextInputType.number,
            inputFormatters: [CpfInputFormatter()],
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null;
              if (!ClientPhoneRules.isValidCpf(v)) return 'CPF inválido';
              return null;
            },
          ),
          right: ClientFormField(
            controller: _rgController,
            label: 'RG',
          ),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 160,
          left: ClientFormField(
            controller: _secondaryPhoneController,
            label: 'Telefone secundário',
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null;
              if (!ClientPhoneRules.isValidPhone(v)) {
                return 'Telefone secundário inválido: informe DDD + número';
              }
              return _phoneDuplicateError('secondaryPhone');
            },
          ),
          right: ClientDateField(
            label: 'Nascimento',
            value: _birthDate,
            icon: Icons.cake_outlined,
            lastDate: DateTime.now(),
            initialPickerDate:
                DateTime.now().subtract(const Duration(days: 365 * 25)),
            pickYearFirst: true,
            onChanged: (date) => setState(() {
              _birthDate = date;
              _birthDateController.text =
                  date == null ? '' : DateFormat('dd/MM/yyyy').format(date);
            }),
          ),
        ),
      ],
    );
  }

  /// Endereço todo opcional (web e back); só o formato é conferido quando o
  /// campo vem preenchido.
  Widget _buildAddressSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientFormRow2(
          leftFlex: 3,
          rightFlex: 2,
          minColumnWidth: 64,
          left: ClientFormField(
            controller: _zipCodeController,
            label: 'CEP',
            keyboardType: TextInputType.number,
            inputFormatters: [CepInputFormatter()],
            validator: (value) {
              final cep = (value ?? '').replaceAll(RegExp(r'[^\d]'), '');
              if ((value ?? '').trim().isEmpty) return null;
              if (cep.length != 8) return 'CEP inválido';
              return null;
            },
          ),
          right: ClientFormField(
            controller: _stateController,
            label: 'UF',
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null;
              if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(v)) {
                return 'Use a sigla (ex.: SP)';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        ClientFormField(
          controller: _addressController,
          label: 'Endereço',
          hint: 'Rua, número e complemento',
          validator: (value) {
            if ((value?.trim().length ?? 0) > 500) {
              return 'Endereço não pode ter mais que 500 caracteres';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 120,
          left: ClientFormField(
            controller: _cityController,
            label: 'Cidade',
            validator: (value) {
              if ((value?.trim().length ?? 0) > 100) {
                return 'Máximo de 100 caracteres';
              }
              return null;
            },
          ),
          right: ClientFormField(
            controller: _neighborhoodController,
            label: 'Bairro',
            validator: (value) {
              if ((value?.trim().length ?? 0) > 100) {
                return 'Máximo de 100 caracteres';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormCaption('Estado civil'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ClientChoiceChip(
              label: 'Não informado',
              color: neutral,
              selected: _selectedMaritalStatus == null,
              onTap: () => setState(() => _selectedMaritalStatus = null),
            ),
            for (final status in MaritalStatus.values)
              ClientChoiceChip(
                label: status.label,
                selected: _selectedMaritalStatus == status,
                onTap: () => setState(() => _selectedMaritalStatus = status),
              ),
          ],
        ),
        if (!_isEdit && _showsSpouse) ...[
          const SizedBox(height: 10),
          _hintLine(
            context,
            Icons.info_outline,
            'O cônjuge é cadastrado depois: salve o cliente e abra a edição '
            'dele para adicionar.',
          ),
        ],
        const SizedBox(height: 14),
        ClientSwitchRow(
          icon: Icons.child_care_outlined,
          title: 'Possui dependentes',
          subtitle: 'Filhos, agregados ou outros',
          value: _hasDependents ?? false,
          onChanged: (v) => setState(() {
            _hasDependents = v;
            if (!v) _numberOfDependents = null;
          }),
        ),
        if (_hasDependents == true) ...[
          const SizedBox(height: 10),
          TextFormField(
            initialValue: _numberOfDependents?.toString() ?? '',
            keyboardType: TextInputType.number,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
            decoration: const InputDecoration(
              label: ClientFieldLabel('Número de dependentes'),
            ),
            onChanged: (value) => _numberOfDependents = int.tryParse(value),
          ),
          const SizedBox(height: 12),
          ClientFormField(
            controller: _dependentsNotesController,
            label: 'Observações sobre dependentes',
            maxLines: 2,
          ),
        ],
      ],
    );
  }

  Widget _buildProfessionalSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormCaption('Situação profissional'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ClientChoiceChip(
              label: 'Não informado',
              color: neutral,
              selected: _selectedEmploymentStatus == null,
              onTap: () => setState(() => _selectedEmploymentStatus = null),
            ),
            for (final status in EmploymentStatus.values)
              ClientChoiceChip(
                label: status.label,
                selected: _selectedEmploymentStatus == status,
                onTap: () => setState(() {
                  _selectedEmploymentStatus = status;
                  _employmentError = null;
                }),
              ),
          ],
        ),
        if (_employmentError != null) ...[
          const SizedBox(height: 8),
          _inlineError(context, _employmentError!),
        ],
        const SizedBox(height: 16),
        ClientFormRow2(
          minColumnWidth: 120,
          left: ClientFormField(
            controller: _companyNameController,
            label: 'Empresa',
          ),
          right: ClientFormField(
            controller: _jobPositionController,
            label: 'Cargo',
            validator: (value) {
              // Regra do web: com renda e situação "empregado" ou
              // "autônomo", o cargo/função passa a ser exigido.
              final working = _selectedEmploymentStatus ==
                      EmploymentStatus.employed ||
                  _selectedEmploymentStatus == EmploymentStatus.selfEmployed;
              if (_hasAnyIncome &&
                  working &&
                  (value?.trim().isEmpty ?? true)) {
                return 'Informe o cargo/função';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: ClientFormField(
            controller: _contractTypeController,
            label: 'Tipo de contrato',
            hint: 'Ex.: CLT, PJ',
          ),
          right: ClientDateField(
            label: 'Início',
            value: _jobStartDate,
            icon: Icons.event_available_outlined,
            lastDate: DateTime.now(),
            onChanged: (d) => setState(() {
              _jobStartDate = d;
              if (d != null &&
                  _jobEndDate != null &&
                  _jobEndDate!.isBefore(d)) {
                _jobEndDate = null;
              }
            }),
          ),
        ),
        const SizedBox(height: 8),
        ClientSwitchRow(
          icon: Icons.work_history_outlined,
          title: 'Ainda está trabalhando',
          subtitle: 'Desligue para informar a data de término',
          value: _isCurrentlyWorking,
          onChanged: (v) => setState(() => _isCurrentlyWorking = v),
        ),
        if (!_isCurrentlyWorking) ...[
          const SizedBox(height: 8),
          ClientDateField(
            label: 'Término',
            value: _jobEndDate,
            icon: Icons.event_busy_outlined,
            // Término nunca antes do início (minDate do web).
            firstDate: _jobStartDate ?? DateTime(1900),
            lastDate: DateTime(2100),
            onChanged: (d) => setState(() => _jobEndDate = d),
          ),
          const SizedBox(height: 4),
        ],
        ClientSwitchRow(
          icon: Icons.work_off_outlined,
          title: 'Aposentado(a)',
          subtitle: 'Recebe aposentadoria como fonte principal',
          value: _isRetired ?? false,
          onChanged: (v) => setState(() {
            _isRetired = v;
            if (v) _employmentError = null;
          }),
        ),
      ],
    );
  }

  Widget _inlineError(BuildContext context, String message) {
    final danger = clientFormDanger(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: danger),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: danger,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
          ),
        ),
      ],
    );
  }

  Widget _hintLine(BuildContext context, IconData icon, String text) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }

  /// Dinheiro na máscara padrão do app (`1.234,56` + prefixo "R$ ").
  Widget _moneyField(TextEditingController controller, String label) {
    return ClientFormField(
      controller: controller,
      label: label,
      hint: '0,00',
      prefixText: 'R\$ ',
      keyboardType: TextInputType.number,
      inputFormatters: [CurrencyInputFormatter()],
    );
  }

  Widget _buildFinancialSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormBand(
          'Renda',
          icon: Icons.payments_outlined,
          topSpacing: 0,
        ),
        ClientFormRow2(
          minColumnWidth: 150,
          left: _moneyField(_monthlyIncomeController, 'Renda mensal'),
          right: _moneyField(_familyIncomeController, 'Renda familiar'),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: _moneyField(_grossSalaryController, 'Salário bruto'),
          right: _moneyField(_netSalaryController, 'Salário líquido'),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: _moneyField(_thirteenthSalaryController, '13º salário'),
          right: _moneyField(_vacationPayController, 'Férias'),
        ),
        const ClientFormBand('Outras rendas', icon: Icons.add_card_outlined),
        ClientFormField(
          controller: _otherIncomeSourcesController,
          label: 'De onde vem',
          hint: 'Ex.: aluguel, pensão, comissões',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        _moneyField(_otherIncomeAmountController, 'Valor das outras rendas'),
        const ClientFormBand('Crédito', icon: Icons.credit_score_outlined),
        ClientFormRow2(
          minColumnWidth: 175,
          left: ClientFormField(
            controller: _creditScoreController,
            label: 'Score de crédito',
            hint: 'De 0 a 1000',
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                final score = int.tryParse(value);
                if (score == null || score < 0 || score > 1000) {
                  return 'O score vai de 0 a 1000';
                }
              }
              return null;
            },
          ),
          right: ClientDateField(
            label: 'Última consulta',
            value: _lastCreditCheck,
            icon: Icons.fact_check_outlined,
            lastDate: DateTime.now(),
            onChanged: (d) => setState(() => _lastCreditCheck = d),
          ),
        ),
        const ClientFormBand('Banco', icon: Icons.account_balance_outlined),
        ClientFormRow2(
          leftFlex: 3,
          rightFlex: 2,
          minColumnWidth: 90,
          left: ClientFormField(
            controller: _bankNameController,
            label: 'Banco',
          ),
          right: ClientFormField(
            controller: _bankAgencyController,
            label: 'Agência',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 14),
        const ClientFormCaption('Tipo de conta'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ClientChoiceChip(
              label: 'Não informado',
              color: neutral,
              selected: _accountType == null,
              onTap: () => setState(() => _accountType = null),
            ),
            for (final account in const [
              ('checking', 'Conta corrente'),
              ('savings', 'Poupança'),
              ('salary', 'Salário'),
            ])
              ClientChoiceChip(
                label: account.$2,
                selected: _accountType == account.$1,
                onTap: () => setState(() => _accountType = account.$1),
              ),
          ],
        ),
        const ClientFormBand(
          'Patrimônio',
          icon: Icons.real_estate_agent_outlined,
        ),
        ClientSwitchRow(
          icon: Icons.house_outlined,
          title: 'Possui imóvel próprio',
          subtitle: 'Patrimônio imobiliário existente',
          value: _hasProperty ?? false,
          onChanged: (v) => setState(() => _hasProperty = v),
        ),
        ClientSwitchRow(
          icon: Icons.directions_car_outlined,
          title: 'Possui veículo',
          subtitle: 'Carro, moto ou outro',
          value: _hasVehicle ?? false,
          onChanged: (v) => setState(() => _hasVehicle = v),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientFormRow2(
          minColumnWidth: 140,
          left: ClientFormField(
            controller: _preferredCityController,
            label: 'Cidade preferida',
          ),
          right: ClientFormField(
            controller: _preferredNeighborhoodController,
            label: 'Bairro preferido',
          ),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: _moneyField(_minValueController, 'Valor mínimo'),
          right: _moneyField(_maxValueController, 'Valor máximo'),
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 110,
          left: ClientFormField(
            controller: _minAreaController,
            label: 'Área mínima',
            suffixText: 'm²',
            keyboardType: TextInputType.number,
          ),
          right: ClientFormField(
            controller: _maxAreaController,
            label: 'Área máxima',
            suffixText: 'm²',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 18),
        const ClientFormCaption('Quartos'),
        ClientFormRow2(
          minColumnWidth: 150,
          left: _stepperField(
            context,
            label: 'Mínimo',
            value: _minBedrooms,
            onChanged: (v) => setState(() => _minBedrooms = v),
          ),
          right: _stepperField(
            context,
            label: 'Máximo',
            value: _maxBedrooms,
            onChanged: (v) => setState(() => _maxBedrooms = v),
          ),
        ),
        const SizedBox(height: 18),
        const ClientFormCaption('Banheiros (mínimo)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ClientChoiceChip(
              label: 'Indiferente',
              color: neutral,
              selected: _minBathrooms == null,
              onTap: () => setState(() => _minBathrooms = null),
            ),
            for (var i = 1; i <= 6; i++)
              ClientChoiceChip(
                label: i == 6 ? '6+' : '$i',
                selected: _minBathrooms == i,
                onTap: () => setState(() => _minBathrooms = i),
              ),
          ],
        ),
      ],
    );
  }

  /// Contador (−/+) no desenho dos campos; vazio = "—" (indiferente).
  Widget _stepperField(
    BuildContext context, {
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    final theme = Theme.of(context);
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InputDecorator(
      decoration: InputDecoration(
        label: ClientFieldLabel(label),
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null ? '—' : '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: value == null ? muted : ThemeHelpers.textColor(context),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Diminuir',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.remove_rounded,
              color: value == null || value == 0
                  ? muted.withValues(alpha: 0.4)
                  : accent,
            ),
            onPressed: value == null || value == 0
                ? null
                : () => onChanged(value - 1 == 0 ? null : value - 1),
          ),
          IconButton(
            tooltip: 'Aumentar',
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

  // ───────────────────────── Características desejadas ─────────────────────────

  Widget _buildDesiredFeaturesSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final hasGarage = _desiredFeatures['hasGarage'] == true;
    final spots = _desiredFeatures['garageSpots'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormCaption(
          'O que o cliente procura',
          hint: 'Toque para marcar; toque de novo para desmarcar.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _kDesiredFeatures)
              ClientChoiceChip(
                label: f.$2,
                icon: f.$3,
                selected: _desiredFeatures[f.$1] == true,
                onTap: () => setState(() {
                  final next = !(_desiredFeatures[f.$1] == true);
                  if (next) {
                    _desiredFeatures[f.$1] = true;
                  } else {
                    _desiredFeatures.remove(f.$1);
                    // Desmarcar garagem tira o número de vagas (web).
                    if (f.$1 == 'hasGarage') {
                      _desiredFeatures.remove('garageSpots');
                    }
                  }
                }),
              ),
          ],
        ),
        if (hasGarage) ...[
          const SizedBox(height: 18),
          const ClientFormCaption('Vagas de garagem'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ClientChoiceChip(
                label: 'Indiferente',
                color: neutral,
                selected: spots is! int,
                onTap: () =>
                    setState(() => _desiredFeatures.remove('garageSpots')),
              ),
              for (var i = 1; i <= 10; i++)
                ClientChoiceChip(
                  label: '$i',
                  selected: spots == i,
                  onTap: () =>
                      setState(() => _desiredFeatures['garageSpots'] = i),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        ClientFormField(
          controller: _otherFeaturesController,
          label: 'Outras características',
          hint: 'Ex.: vista para o mar, lareira (separe por vírgula)',
          maxLines: 2,
        ),
      ],
    );
  }

  // ───────────────────────── Cônjuge ─────────────────────────

  bool get _showsSpouse =>
      _selectedMaritalStatus == MaritalStatus.married ||
      _selectedMaritalStatus == MaritalStatus.commonLaw;

  Widget _buildSpouseSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final danger = clientFormDanger(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    final spouse = _spouse;
    if (spouse == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nenhum cônjuge cadastrado. Estes dados alimentam os signatários '
            'das fichas.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openSpouseSheet(),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Adicionar cônjuge',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.45)),
              padding: buttonPadding,
              shape: buttonShape,
            ),
          ),
        ],
      );
    }

    final details = <String>[
      if ((spouse.cpf ?? '').isNotEmpty) 'CPF ${Masks.cpf(spouse.cpf!)}',
      if ((spouse.phone ?? '').isNotEmpty)
        ClientPhoneRules.maskAuto(spouse.phone),
      if ((spouse.email ?? '').isNotEmpty) spouse.email!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
              ),
              child: Text(
                _initialsOf(spouse.name),
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 110,
          left: OutlinedButton.icon(
            onPressed: _confirmDeleteSpouse,
            icon: Icon(Icons.delete_outline, size: 18, color: danger),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Remover',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: danger, fontWeight: FontWeight.w700),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: danger,
              side: BorderSide(color: danger.withValues(alpha: 0.45)),
              padding: buttonPadding,
              shape: buttonShape,
            ),
          ),
          right: OutlinedButton.icon(
            onPressed: () => _openSpouseSheet(initial: spouse),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Editar',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              padding: buttonPadding,
              shape: buttonShape,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSpouseSheet({Spouse? initial}) async {
    final client = _client;
    if (client == null) return;
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        // Superfície Material: o toque dos interruptores aparece por cima
        // do fundo da folha. Cabeçalho, rolagem e botões ficam no SpouseForm.
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
            child: Material(
              color: ThemeHelpers.backgroundColor(ctx),
              clipBehavior: Clip.antiAlias,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: SpouseForm(
                initialSpouse: initial,
                clientPhone: _phoneController.text,
                clientSecondaryPhone: _secondaryPhoneController.text,
                clientWhatsapp: _whatsappController.text,
                onCancel: () => Navigator.pop(ctx),
                onSave: (spouse) async {
                  final response = initial == null
                      ? await ClientService.instance
                          .createSpouse(client.id, spouse)
                      : await ClientService.instance
                          .updateSpouse(initial.id, spouse);
                  if (!mounted) return false;
                  if (response.success && response.data != null) {
                    setState(() => _spouse = response.data);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSnack(
                      initial == null
                          ? 'Cônjuge cadastrado com sucesso!'
                          : 'Cônjuge atualizado com sucesso!',
                    );
                    return true;
                  }
                  _showSnack(
                    response.message ?? 'Erro ao salvar cônjuge',
                    error: true,
                  );
                  return false;
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSpouse() async {
    final spouse = _spouse;
    if (spouse == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Remover cônjuge?'),
        content: Text(
          'Os dados de ${spouse.name} saem do cadastro deste cliente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: clientFormDanger(ctx),
              foregroundColor: Colors.white,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final response = await ClientService.instance.deleteSpouse(spouse.id);
    if (!mounted) return;
    if (response.success) {
      setState(() => _spouse = null);
      _showSnack('Cônjuge removido.');
    } else {
      _showSnack(response.message ?? 'Erro ao remover cônjuge', error: true);
    }
  }

  Widget _buildReferencesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClientFormBand(
          'Referência pessoal',
          icon: Icons.person_outline,
          topSpacing: 0,
        ),
        ClientFormField(
          controller: _referenceNameController,
          label: 'Nome',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: ClientFormField(
            controller: _referencePhoneController,
            label: 'Telefone',
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
          ),
          right: ClientFormField(
            controller: _referenceRelationshipController,
            label: 'Relacionamento',
            hint: 'Ex.: irmã, amigo',
          ),
        ),
        const ClientFormBand(
          'Referência profissional',
          icon: Icons.business_center_outlined,
        ),
        ClientFormField(
          controller: _professionalReferenceNameController,
          label: 'Nome',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        ClientFormRow2(
          minColumnWidth: 150,
          left: ClientFormField(
            controller: _professionalReferencePhoneController,
            label: 'Telefone',
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
          ),
          right: ClientFormField(
            controller: _professionalReferencePositionController,
            label: 'Cargo',
          ),
        ),
      ],
    );
  }

  Widget _buildMcmvSection(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientSwitchRow(
          icon: Icons.house_siding_outlined,
          title: 'Interessado no MCMV',
          subtitle: 'Abre os campos do programa',
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
          ClientSwitchRow(
            icon: Icons.verified_outlined,
            title: 'Elegível para o MCMV',
            subtitle: 'Validado pela equipe ou por simulação',
            value: _mcmvEligible ?? false,
            onChanged: (v) => setState(() => _mcmvEligible = v),
          ),
          const SizedBox(height: 14),
          const ClientFormCaption('Faixa de renda do programa'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ClientChoiceChip(
                label: 'Não informada',
                color: neutral,
                selected: _mcmvIncomeRange == null,
                onTap: () => setState(() => _mcmvIncomeRange = null),
              ),
              for (final range in const [
                ('faixa1', 'Faixa 1'),
                ('faixa2', 'Faixa 2'),
                ('faixa3', 'Faixa 3'),
              ])
                ClientChoiceChip(
                  label: range.$2,
                  selected: _mcmvIncomeRange == range.$1,
                  onTap: () => setState(() => _mcmvIncomeRange = range.$1),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClientFormField(
            controller: _mcmvCadunicoNumberController,
            label: 'Número do CadÚnico',
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }

  // ───────────────────────── Erros ─────────────────────────

  /// Depois de um salvar recusado, leva a tela até o primeiro campo com erro
  /// (ou até a seção profissional, quando a pendência é a situação).
  void _revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Seções recolhidas continuam validando (ficam Offstage): abre toda
      // seção que tem campo com erro antes de rolar até o primeiro.
      final withError = _fieldsWithError();
      for (final field in withError) {
        ClientFormSection.revealAncestors(field);
      }
      final target = (withError.isNotEmpty ? withError.first : null) ??
          (_employmentError != null
              ? _professionalSectionKey.currentContext
              : null);
      if (target == null) return;
      // Espera a seção abrir (220 ms) para medir a posição certa.
      Future<void>.delayed(
        Duration(milliseconds: withError.isNotEmpty ? 260 : 0),
        () {
          if (!mounted || !target.mounted) return;
          Scrollable.ensureVisible(
            target,
            alignment: 0.15,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        },
      );
    });
  }

  /// Todos os campos com erro, na ordem da árvore (inclusive os de seções
  /// recolhidas, que seguem montadas).
  List<BuildContext> _fieldsWithError() {
    final root = _formKey.currentContext;
    if (root == null) return const [];
    final out = <BuildContext>[];
    void visit(Element element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is FormFieldState && state.hasError) {
          out.add(element);
          return;
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return out;
  }

  // ───────────────────────── Helpers ─────────────────────────

  /// Cor do tipo — tokens de status; o ciano de "Locador" não tem token
  /// equivalente e segue o mesmo da lista de clientes.
  Color _typeColor(BuildContext context, ClientType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case ClientType.buyer:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case ClientType.seller:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case ClientType.renter:
        return isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case ClientType.lessor:
        return const Color(0xFF06B6D4);
      case ClientType.investor:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      case ClientType.general:
        return ThemeHelpers.textSecondaryColor(context);
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

  Color _statusColor(BuildContext context, ClientStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case ClientStatus.active:
        return isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case ClientStatus.inactive:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case ClientStatus.contacted:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case ClientStatus.interested:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case ClientStatus.closed:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }
}

/// Iniciais para avatar (primeiro e último nome).
String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Folha de seleção do captador (lista com busca): altura máxima de 88%,
/// teclado respeitado e, se a lista não carregou, "Tentar de novo".
class _CapturerPickerSheet extends StatefulWidget {
  const _CapturerPickerSheet({
    required this.users,
    required this.selectedId,
    required this.currentUserId,
    required this.onReload,
  });

  final List<UserInfo> users;
  final String? selectedId;
  final String? currentUserId;
  final Future<List<UserInfo>> Function() onReload;

  @override
  State<_CapturerPickerSheet> createState() => _CapturerPickerSheetState();
}

class _CapturerPickerSheetState extends State<_CapturerPickerSheet> {
  String _query = '';
  late List<UserInfo> _users = widget.users;
  bool _reloading = false;

  Future<void> _reload() async {
    setState(() => _reloading = true);
    final users = await widget.onReload();
    if (!mounted) return;
    setState(() {
      _users = users;
      _reloading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final q = _query.trim().toLowerCase();
    final users = _users.where((u) {
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: Material(
          color: ThemeHelpers.backgroundColor(context),
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Theme(
            data: clientFormTheme(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Captador',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            Text(
                              'Quem trouxe este cliente',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: Icon(Icons.close_rounded, color: muted),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome ou e-mail',
                      prefixIcon:
                          Icon(Icons.search_rounded, color: muted, size: 20),
                    ),
                  ),
                ),
                Flexible(
                  child: users.isEmpty
                      ? SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            16,
                            24,
                            24 + media.padding.bottom,
                          ),
                          child: _buildEmpty(context),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.fromLTRB(
                            8,
                            4,
                            8,
                            16 + media.padding.bottom,
                          ),
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final u = users[index];
                            final selected = u.id == widget.selectedId;
                            final isMe = u.id == widget.currentUserId;
                            return ListTile(
                              onTap: () => Navigator.pop(context, u.id),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              selected: selected,
                              selectedTileColor: accent.withValues(
                                alpha: isDark ? 0.14 : 0.08,
                              ),
                              leading: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent.withValues(
                                    alpha: isDark ? 0.2 : 0.1,
                                  ),
                                ),
                                child: Text(
                                  _initialsOf(u.name),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: accent,
                                  ),
                                ),
                              ),
                              title: Text(
                                isMe ? '${u.name} (você)' : u.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeHelpers.textColor(context),
                                ),
                              ),
                              subtitle: u.email.isEmpty
                                  ? null
                                  : Text(
                                      u.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: muted,
                                      ),
                                    ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: clientFormSuccess(context),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Vazio que explica: lista que não carregou (com "Tentar de novo") ou
  /// busca sem resultado.
  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final failed = _users.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          failed ? Icons.cloud_off_outlined : Icons.person_search_outlined,
          size: 30,
          color: muted,
        ),
        const SizedBox(height: 10),
        Text(
          failed
              ? 'Não foi possível carregar os usuários da empresa.'
              : 'Ninguém encontrado com "${_query.trim()}".',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          failed
              ? 'Verifique a conexão e tente de novo.'
              : 'Busque pelo nome ou pelo e-mail.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        if (failed) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _reloading ? null : _reload,
            icon: _reloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar de novo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
