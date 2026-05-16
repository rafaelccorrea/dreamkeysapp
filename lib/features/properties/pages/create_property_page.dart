import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/gallery_service.dart';
import '../../../../shared/services/cep_service.dart';
import '../../../../shared/services/ai_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/utils/input_formatters.dart';
import '../../../../shared/utils/masks.dart';
import '../../../../shared/utils/image_crop_helper.dart';
import '../../../../core/navigation/adaptive_page_route.dart';
import '../../../../core/routes/app_routes.dart';
import '../models/property_local_draft.dart';
import '../models/property_wizard_pop_result.dart';
import '../services/property_local_draft_storage.dart';
import '../widgets/property_creation_setup_modal.dart';
import 'package:intl/intl.dart';
import '../../../../shared/utils/property_form_config.dart';

/// Página de criação/edição de propriedade com formulário multi-etapas
class CreatePropertyPage extends StatefulWidget {
  final String? propertyId; // Se fornecido, é edição
  /// Continuação de rascunho salvo apenas neste dispositivo.
  final String? localDraftId;

  const CreatePropertyPage({super.key, this.propertyId, this.localDraftId});

  @override
  State<CreatePropertyPage> createState() => _CreatePropertyPageState();
}

class _CreatePropertyPageState extends State<CreatePropertyPage> {
  final PageController _pageController = PageController();
  final PropertyService _propertyService = PropertyService.instance;

  int _currentStep = 0;
  final int _totalSteps = 7; // Adicionada etapa de revisão

  static const List<String> _wizardTitles = [
    'Informações básicas',
    'Localização',
    'Medidas e detalhes',
    'Valores',
    'Galeria de fotos',
    'Proprietário',
    'Revisão final',
  ];

  static const List<String> _wizardSubtitles = [
    'Tipo do imóvel e texto do anúncio (ou deixe a IA gerar na revisão).',
    'Informe o CEP para completar ou confira o endereço manualmente.',
    'Áreas, cômodos e diferenciais do imóvel.',
    'Venda, aluguel, taxas e regras de negociação.',
    'Mínimo de 2 fotos para continuar (mesmo fluxo do CRM web).',
    'Dados do proprietário — clientes interessados são opcionais.',
    'Revise com calma ou refine título e descrição com IA.',
  ];

  static const EdgeInsets _wizScrollPadding =
      EdgeInsets.fromLTRB(14, 6, 14, 44);
  static const double _wizGapAfterHeader = 22;
  static const double _wizGapBetweenSections = 22;

  /// Identidade visual por etapa (ícone + cor de acento) — usada no stepper,
  /// no hero da etapa e na faixa lateral das seções.
  static const List<({IconData icon, Color color})> _wizStepIdentity = [
    (icon: Icons.auto_awesome_rounded, color: Color(0xFF6366F1)),
    (icon: Icons.location_on_rounded, color: Color(0xFF0EA5E9)),
    (icon: Icons.straighten_rounded, color: Color(0xFF14B8A6)),
    (icon: Icons.payments_rounded, color: Color(0xFF10B981)),
    (icon: Icons.photo_library_rounded, color: Color(0xFFA855F7)),
    (icon: Icons.badge_rounded, color: Color(0xFFF59E0B)),
    (icon: Icons.fact_check_rounded, color: Color(0xFFD32F2F)),
  ];

  Color _stepAccent(int step) =>
      _wizStepIdentity[step.clamp(0, _totalSteps - 1)].color;
  IconData _stepIcon(int step) =>
      _wizStepIdentity[step.clamp(0, _totalSteps - 1)].icon;

  // Controllers do formulário
  final _formKey = GlobalKey<FormState>();

  // Etapa 1: Informações Básicas
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _internalNotesController = TextEditingController();
  PropertyType _selectedType = PropertyType.house;

  // Etapa 2: Localização
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _sectorController = TextEditingController();

  // Etapa 3: Características
  final _totalAreaController = TextEditingController();
  final _builtAreaController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _parkingSpacesController = TextEditingController();
  final _suitesController = TextEditingController();
  final List<String> _selectedFeatures = [];

  // Etapa 4: Valores
  final _salePriceController = TextEditingController();
  final _rentPriceController = TextEditingController();
  final _condominiumFeeController = TextEditingController();
  final _iptuController = TextEditingController();
  bool _acceptsNegotiation = false;
  final _minSalePriceController = TextEditingController();
  final _minRentPriceController = TextEditingController();
  String? _offerBelowMinSaleAction;
  String? _offerBelowMinRentAction;

  // Etapa 5: Galeria
  final List<File> _selectedImages = [];
  final List<GalleryImage> _uploadedImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingImages = false;

  // Etapa 6: Clientes e Proprietário
  final List<String> _selectedClientIds = []; // TODO: Buscar clientes reais

  // Serviços
  final GalleryService _galleryService = GalleryService.instance;
  final CepService _cepService = CepService.instance;
  final AiService _aiService = AiService.instance;

  // IA
  final List<GeneratedDescription> _generatedVariants = [];
  bool _isGeneratingDescription = false;
  bool _autoGenerateOnReview = true; // Auto-gerar na revisão por padrão
  bool _hasAutoGeneratedOnReview = false; // Flag para evitar múltiplas gerações

  // Proprietário (obrigatórios)
  final _ownerNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _ownerDocumentController = TextEditingController();
  final _ownerAddressController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingProperty = false;
  /// ID do usuário logado (`capturedById` obrigatório no POST `/properties` do backend).
  String? _currentUserId;

  static const int _kMinGalleryImagesWeb = 2;
  static const int _kMaxGalleryImagesWeb = 50;

  /// Paridade `propertyApi.getApprovalSettingsActive()` + `buildCreatePropertyApiPayload.ts`.
  bool _requireApprovalToBeAvailable = false;
  bool _requireApprovalToPublishOnSite = false;
  bool _requireOwnerAuthorizationToBeAvailable = false;
  bool _preservePublicationOnEdit = true;
  bool _approvalSettingsLoaded = false;
  /// `true` somente após `GET /properties/approval-settings/active` com sucesso.
  bool _approvalSettingsFetchOk = false;
  Future<void>? _approvalSettingsLoadFuture;

  /// `GET /properties/form-settings` — espelha `assertConfigurableRequiredFieldsMet` do backend.
  List<String> _formRequiredKeys = [];
  List<PropertyFormTeamOption> _formTeams = [];
  List<NamedEntityOption> _condominiumOptions = [];
  List<NamedEntityOption> _empreendimentoOptions = [];
  bool _formSettingsFetchOk = false;
  Future<void>? _formSettingsLoadFuture;
  String? _selectedTeamId;
  String? _selectedCondominiumId;
  String? _selectedEmpreendimentoId;

  /// Modo de origem do endereço — paridade web (`PropertyCreationSetupPayload`).
  PropertyCreationAddressMode _addressMode =
      PropertyCreationAddressMode.standalone;
  /// Nome da entidade vinculada (para mostrar no Step 2 — "endereço vem de X").
  String? _addressLinkedEntityName;
  /// Garante que o setup modal só é aberto uma vez automaticamente.
  bool _setupModalAlreadyShown = false;
  /// Controla "carregando endereço do cadastro" (cond/emp).
  bool _isPrefillingFromLinkedEntity = false;

  /// Auto-save anônimo do form (paridade `localStorage` web).
  /// Debounced em ~500ms — guarda todo o estado em
  /// `PropertyLocalDraftStorage.saveAnonymous` para sobreviver a rebuilds.
  Timer? _anonymousAutoSaveTimer;
  bool _anonymousDraftRestored = false;
  bool _isApplyingAnonymousDraft = false;
  bool _suppressAnonymousAutoSave = false;

  /// Formulário: default web `getDefaultFormData().isAvailableForSite === false`.
  bool _publishToSite = false;
  /// Quando não há fila obrigatória, espelha o seletor rascunho/disponível do web.
  bool _listingStatusIsDraft = true;
  bool _isFeatured = false;

  /// Edição — snapshot para `preservePublicationOnEdit` (omitir campos quando inalterados).
  String? _loadedPropertyStatus;
  bool? _loadedPropertyIsAvailableForSite;
  int _serverImageCountAtLoad = 0;

  String? _loadedCapturedById;

  final PropertyLocalDraftStorage _draftStorage =
      PropertyLocalDraftStorage.instance;
  /// ID do rascunho local em edição (novo ou reaberto da lista).
  String? _activeLocalDraftId;
  String? _activeLocalDraftDisplayTitle;
  bool _isHydratingLocalDraft = false;

  @override
  void initState() {
    super.initState();
    _approvalSettingsLoadFuture = _loadApprovalSettings();
    _formSettingsLoadFuture = _loadFormSettings();
    _loadCurrentUserId();
    if (widget.propertyId != null) {
      _loadProperty();
    } else if (widget.localDraftId != null &&
        widget.localDraftId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadLocalDraft(widget.localDraftId!);
      });
    } else {
      // Criação fresca: tenta restaurar rascunho anônimo do dispositivo
      // (paridade `localStorage.getItem(DRAFT_STORAGE_KEY)` do web).
      // Só abre o modal de pré-criação se não houver rascunho válido.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreAnonymousDraftThenMaybeOpenSetup();
      });
    }

    // Adicionar listeners para revalidar quando os campos mudarem
    _titleController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _streetController.addListener(_onFieldChanged);
    _numberController.addListener(_onFieldChanged);
    _neighborhoodController.addListener(_onFieldChanged);
    _cityController.addListener(_onFieldChanged);
    _stateController.addListener(_onFieldChanged);
    _zipCodeController.addListener(_onFieldChanged);
    _zipCodeController.addListener(_onCepChanged);
    _totalAreaController.addListener(_onFieldChanged);
    _builtAreaController.addListener(_onFieldChanged);
    _ownerNameController.addListener(_onFieldChanged);
    _ownerEmailController.addListener(_onFieldChanged);
    _ownerPhoneController.addListener(_onFieldChanged);
    _ownerDocumentController.addListener(_onFieldChanged);
    _ownerAddressController.addListener(_onFieldChanged);
    _sectorController.addListener(_onFieldChanged);
    _internalNotesController.addListener(_onFieldChanged);
    _suitesController.addListener(_onFieldChanged);
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final response = await ProfileService.instance.getProfile();
      if (response.success &&
          response.data != null &&
          response.data!.id.isNotEmpty &&
          mounted) {
        setState(() => _currentUserId = response.data!.id);
      }
    } catch (e) {
      debugPrint('Erro ao carregar ID do usuário: $e');
    }
  }

  Future<void> _loadApprovalSettings() async {
    try {
      final r = await _propertyService.getPropertyApprovalSettingsActive();
      if (!mounted) return;
      if (r.success && r.data != null) {
        final s = r.data!;
        setState(() {
          _requireApprovalToBeAvailable = s.requireApprovalToBeAvailable;
          _requireApprovalToPublishOnSite = s.requireApprovalToPublishOnSite;
          _requireOwnerAuthorizationToBeAvailable =
              s.requireOwnerAuthorizationToBeAvailable;
          _preservePublicationOnEdit = s.preservePublicationOnEdit;
          _approvalSettingsLoaded = true;
          _approvalSettingsFetchOk = true;
        });
      } else {
        setState(() {
          _approvalSettingsLoaded = true;
          _approvalSettingsFetchOk = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar approval-settings: $e');
      if (mounted) {
        setState(() {
          _approvalSettingsLoaded = true;
          _approvalSettingsFetchOk = false;
        });
      }
    }
  }

  Future<void> _loadFormSettings() async {
    try {
      final r = await _propertyService.getPropertyFormSettings();
      if (!mounted) return;
      if (r.success && r.data != null) {
        final b = r.data!;
        setState(() {
          _formRequiredKeys = List<String>.from(b.propertyFormRequiredFields);
          _formTeams = b.teams;
          _formSettingsFetchOk = true;
        });
        final needCondo = _formRequiredKeys.contains('condominiumId');
        final needEmp = _formRequiredKeys.contains('empreendimentoId');
        if (needCondo) {
          final c = await _propertyService.listCondominiumsBrief();
          if (mounted && c.success && c.data != null) {
            setState(() => _condominiumOptions = c.data!);
          }
        }
        if (needEmp) {
          final e = await _propertyService.listEmpreendimentosBrief();
          if (mounted && e.success && e.data != null) {
            setState(() => _empreendimentoOptions = e.data!);
          }
        }
        if (widget.propertyId == null &&
            _selectedTeamId == null &&
            _formTeams.length == 1 &&
            mounted) {
          setState(() => _selectedTeamId = _formTeams.first.id);
        }
      } else {
        if (mounted) {
          setState(() => _formSettingsFetchOk = false);
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar form-settings: $e');
      if (mounted) setState(() => _formSettingsFetchOk = false);
    }
  }

  Future<void> _ensureFormSettingsBeforeSave() async {
    await (_formSettingsLoadFuture ??= _loadFormSettings());
    if (!_formSettingsFetchOk && mounted) {
      debugPrint('↻ Retry: form-settings antes de salvar');
      _formSettingsLoadFuture = _loadFormSettings();
      await _formSettingsLoadFuture;
    }
  }

  // -------------------------- Anonymous auto-save -------------------------
  //
  // Paridade web: `localStorage.setItem(DRAFT_STORAGE_KEY, ...)` em debounce
  // de ~400-500 ms enquanto o usuário preenche o formulário. Restaurado no
  // próximo abrir da tela de criação para que rebuilds não percam progresso.

  /// Lê o rascunho anônimo. Se contém tipo + teamId, aplica e dispensa o
  /// modal de pré-criação automático (mesma regra do `inferCreationSetupFromDraft`
  /// do web). Caso contrário, abre o modal como sempre.
  Future<void> _restoreAnonymousDraftThenMaybeOpenSetup() async {
    if (!mounted || _setupModalAlreadyShown) return;
    Map<String, dynamic>? draft;
    try {
      draft = await _draftStorage.getAnonymous();
    } catch (_) {
      draft = null;
    }
    if (!mounted) return;

    final hasUsableDraft = _isUsableAnonymousDraft(draft);
    if (hasUsableDraft) {
      _isApplyingAnonymousDraft = true;
      _suppressAnonymousAutoSave = true;
      try {
        setState(() {
          _applyFrozenFormState(draft);
          _anonymousDraftRestored = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final step = _currentStep.clamp(0, _totalSteps - 1);
          try {
            _pageController.jumpToPage(step);
          } catch (_) {
            /* ignore */
          }
        });
      } finally {
        _isApplyingAnonymousDraft = false;
        _suppressAnonymousAutoSave = false;
      }
      _setupModalAlreadyShown = true;
      return;
    }

    _setupModalAlreadyShown = true;
    _openPropertyCreationSetup(isInitial: true);
  }

  /// Considera o rascunho usável quando tem `type` E `teamId` definidos
  /// (mesmas regras do `inferCreationSetupFromDraft` web).
  bool _isUsableAnonymousDraft(Map<String, dynamic>? draft) {
    if (draft == null || draft.isEmpty) return false;
    final type = draft['type']?.toString();
    final teamId = draft['selectedTeamId']?.toString();
    if (type == null || type.isEmpty) return false;
    if (teamId == null || teamId.isEmpty) return false;
    return true;
  }

  void _scheduleAnonymousAutoSave() {
    if (widget.propertyId != null) return; // edição não persiste rascunho
    if (_isApplyingAnonymousDraft || _suppressAnonymousAutoSave) return;
    _anonymousAutoSaveTimer?.cancel();
    _anonymousAutoSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _flushAnonymousAutoSave();
    });
  }

  /// `setState` que também agenda o auto-save anônimo. Usar em mudanças
  /// de toggle/chip/segmented que não passam pelos `TextEditingController`
  /// (que já disparam `_onFieldChanged` → `_scheduleAnonymousAutoSave`).
  void _setStateAndPersist(VoidCallback fn) {
    setState(fn);
    _scheduleAnonymousAutoSave();
  }

  Future<void> _flushAnonymousAutoSave() async {
    if (widget.propertyId != null) return;
    try {
      final snapshot = _freezeFormState();
      await _draftStorage.saveAnonymous(snapshot);
    } catch (e) {
      debugPrint('Auto-save de rascunho anônimo falhou: $e');
    }
  }

  Future<void> _clearAnonymousDraft() async {
    _anonymousAutoSaveTimer?.cancel();
    try {
      await _draftStorage.clearAnonymous();
    } catch (_) {
      /* ignore */
    }
    if (mounted) {
      setState(() => _anonymousDraftRestored = false);
    }
  }

  Future<void> _confirmDiscardAnonymousDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar rascunho?'),
        content: const Text(
          'Tudo o que você preencheu até agora será apagado deste dispositivo. '
          'Você poderá começar um cadastro novo em seguida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _clearAnonymousDraft();
    if (!mounted) return;
    // Reseta os controllers e estado para começar do zero — depois reabre
    // o setup modal para forçar o usuário a configurar novamente.
    _resetWizardForFreshStart();
    _setupModalAlreadyShown = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _setupModalAlreadyShown) return;
      _setupModalAlreadyShown = true;
      _openPropertyCreationSetup(isInitial: true);
    });
  }

  void _resetWizardForFreshStart() {
    _suppressAnonymousAutoSave = true;
    setState(() {
      _titleController.text = '';
      _descriptionController.text = '';
      _internalNotesController.text = '';
      _streetController.text = '';
      _numberController.text = '';
      _complementController.text = '';
      _neighborhoodController.text = '';
      _cityController.text = '';
      _stateController.text = '';
      _zipCodeController.text = '';
      _sectorController.text = '';
      _totalAreaController.text = '';
      _builtAreaController.text = '';
      _bedroomsController.text = '';
      _bathroomsController.text = '';
      _parkingSpacesController.text = '';
      _suitesController.text = '';
      _salePriceController.text = '';
      _rentPriceController.text = '';
      _condominiumFeeController.text = '';
      _iptuController.text = '';
      _minSalePriceController.text = '';
      _minRentPriceController.text = '';
      _ownerNameController.text = '';
      _ownerEmailController.text = '';
      _ownerPhoneController.text = '';
      _ownerDocumentController.text = '';
      _ownerAddressController.text = '';
      _selectedFeatures.clear();
      _selectedClientIds.clear();
      _generatedVariants.clear();
      _selectedImages.clear();
      _uploadedImages.clear();
      _selectedType = PropertyType.house;
      _selectedTeamId = null;
      _selectedCondominiumId = null;
      _selectedEmpreendimentoId = null;
      _addressMode = PropertyCreationAddressMode.standalone;
      _addressLinkedEntityName = null;
      _acceptsNegotiation = false;
      _publishToSite = false;
      _listingStatusIsDraft = true;
      _isFeatured = false;
      _autoGenerateOnReview = true;
      _hasAutoGeneratedOnReview = false;
      _offerBelowMinSaleAction = null;
      _offerBelowMinRentAction = null;
      _currentStep = 0;
      _anonymousDraftRestored = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _pageController.jumpToPage(0);
        } catch (_) {/* ignore */}
        _suppressAnonymousAutoSave = false;
      }
    });
  }

  /// Abre o modal de pré-criação de imóvel — paridade `PropertyCreationSetupModal` web.
  ///
  /// `isInitial=true`: chamada automática no `initState` (1ª vez); ao fechar
  /// sem confirmar, o usuário sai do cadastro (volta para a lista).
  ///
  /// `isInitial=false`: aberto pelo botão "Ajustar configuração" no header
  /// do wizard; ao fechar sem confirmar, mantém os valores atuais.
  Future<void> _openPropertyCreationSetup({required bool isInitial}) async {
    final result = await Navigator.of(context).push<PropertyCreationSetupResult>(
      adaptivePageRoute<PropertyCreationSetupResult>(
        fullscreenDialog: true,
        builder: (_) => PropertyCreationSetupPage(
          initialType: isInitial ? null : _selectedType,
          initialAddressMode: _addressMode,
          initialCondominiumId: _selectedCondominiumId,
          initialEmpreendimentoId: _selectedEmpreendimentoId,
          initialTeamId: _selectedTeamId,
        ),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      if (isInitial) {
        Navigator.of(context).pop();
      }
      return;
    }
    _applySetupResult(result);
  }

  void _applySetupResult(PropertyCreationSetupResult r) {
    final wasExternal = _addressMode != PropertyCreationAddressMode.standalone;
    final goingStandalone =
        r.addressMode == PropertyCreationAddressMode.standalone;
    final shouldResetGeo = wasExternal && goingStandalone;

    setState(() {
      _selectedType = r.type;
      _selectedTeamId = r.teamId;
      _addressMode = r.addressMode;
      _selectedCondominiumId =
          r.addressMode == PropertyCreationAddressMode.condominium
              ? r.condominiumId
              : null;
      _selectedEmpreendimentoId =
          r.addressMode == PropertyCreationAddressMode.empreendimento
              ? r.empreendimentoId
              : null;
      _addressLinkedEntityName =
          r.addressMode == PropertyCreationAddressMode.condominium
              ? r.condominiumName
              : r.addressMode == PropertyCreationAddressMode.empreendimento
                  ? r.empreendimentoName
                  : null;

      if (shouldResetGeo) {
        _zipCodeController.text = '';
        _streetController.text = '';
        _numberController.text = '';
        _neighborhoodController.text = '';
        _cityController.text = '';
        _stateController.text = '';
        _sectorController.text = '';
      }
    });

    if (r.addressMode == PropertyCreationAddressMode.condominium &&
        (r.condominiumId ?? '').isNotEmpty) {
      _prefillAddressFromCondominium(r.condominiumId!);
    } else if (r.addressMode == PropertyCreationAddressMode.empreendimento &&
        (r.empreendimentoId ?? '').isNotEmpty) {
      _prefillAddressFromEmpreendimento(r.empreendimentoId!);
    }
    // Persistir imediatamente após o setup — momento crítico para não
    // perder configuração se o usuário fechar o app antes de digitar mais.
    _flushAnonymousAutoSave();
  }

  Future<void> _prefillAddressFromCondominium(String id) async {
    if (!mounted) return;
    setState(() => _isPrefillingFromLinkedEntity = true);
    final r = await _propertyService.getCondominiumById(id);
    if (!mounted) return;
    setState(() => _isPrefillingFromLinkedEntity = false);
    if (!r.success || r.data == null) return;
    _applyLinkedEntityAddress(r.data!);
  }

  Future<void> _prefillAddressFromEmpreendimento(String id) async {
    if (!mounted) return;
    setState(() => _isPrefillingFromLinkedEntity = true);
    final r = await _propertyService.getEmpreendimentoById(id);
    if (!mounted) return;
    setState(() => _isPrefillingFromLinkedEntity = false);
    if (!r.success || r.data == null) return;
    _applyLinkedEntityAddress(r.data!);
  }

  void _applyLinkedEntityAddress(NamedEntityWithAddress e) {
    String? mask8(String? raw) {
      if (raw == null) return null;
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 8) return raw;
      final d = digits.substring(0, 8);
      return '${d.substring(0, 5)}-${d.substring(5, 8)}';
    }

    setState(() {
      _addressLinkedEntityName = e.name.isNotEmpty ? e.name : null;
      // Sobrescreve campos vazios — preserva edições do usuário, igual ao web
      // (`pickFirstNonEmpty(raw.field, prev.field)`).
      if (_zipCodeController.text.trim().isEmpty && e.zipCode != null) {
        _zipCodeController.text = mask8(e.zipCode) ?? e.zipCode!;
      }
      if (_streetController.text.trim().isEmpty && e.street != null) {
        _streetController.text = e.street!;
      }
      if (_numberController.text.trim().isEmpty && e.number != null) {
        _numberController.text = e.number!;
      }
      if (_neighborhoodController.text.trim().isEmpty &&
          e.neighborhood != null) {
        _neighborhoodController.text = e.neighborhood!;
      }
      if (_cityController.text.trim().isEmpty && e.city != null) {
        _cityController.text = e.city!;
      }
      if (_stateController.text.trim().isEmpty && e.state != null) {
        _stateController.text = e.state!.toUpperCase();
      }
    });
  }

  Future<void> _ensurePreSubmitConfigLoaded() async {
    await _ensureApprovalSettingsBeforeSave();
    await _ensureFormSettingsBeforeSave();
  }

  /// Ao editar, carrega listas para exibir nomes nos seletores.
  void _scheduleLoadPickerListsIfNeeded() {
    if (_selectedCondominiumId != null && _condominiumOptions.isEmpty) {
      _propertyService.listCondominiumsBrief().then((r) {
        if (!mounted || !r.success || r.data == null) return;
        setState(() => _condominiumOptions = r.data!);
      });
    }
    if (_selectedEmpreendimentoId != null && _empreendimentoOptions.isEmpty) {
      _propertyService.listEmpreendimentosBrief().then((r) {
        if (!mounted || !r.success || r.data == null) return;
        setState(() => _empreendimentoOptions = r.data!);
      });
    }
  }

  /// Garante que as flags de aprovação estão atualizadas antes de montar o payload
  /// (evita `Company ID` ainda indisponível na 1ª requisição ou falha transitória).
  Future<void> _ensureApprovalSettingsBeforeSave() async {
    await (_approvalSettingsLoadFuture ??= _loadApprovalSettings());
    if (!_approvalSettingsFetchOk && mounted) {
      debugPrint(
        '↻ Retry: approval-settings antes de salvar (primeira carga indisponível)',
      );
      _approvalSettingsLoadFuture = _loadApprovalSettings();
      await _approvalSettingsLoadFuture;
    }
  }

  double? _parseBrazilianAreaToNumber(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final noThousands = t.replaceAll('.', '');
    final normalized = noThousands.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  int _totalSelectableImageCount() {
    if (widget.propertyId != null) {
      return _serverImageCountAtLoad + _selectedImages.length;
    }
    return _selectedImages.length + _uploadedImages.length;
  }

  void _onFieldChanged() {
    // Revalidar quando os campos mudarem para atualizar o estado do botão
    if (mounted) {
      setState(() {
        // Apenas força rebuild para atualizar o botão
      });
    }
    _scheduleAnonymousAutoSave();
  }

  void _onCepChanged() {
    // Buscar CEP automaticamente quando tiver 8 dígitos
    final cep = _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length == 8) {
      // Aguardar um pouco para o usuário terminar de digitar
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted &&
            _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '').length ==
                8) {
          _searchCep();
        }
      });
    }
  }

  @override
  void dispose() {
    // Remover listeners
    _titleController.removeListener(_onFieldChanged);
    _descriptionController.removeListener(_onFieldChanged);
    _streetController.removeListener(_onFieldChanged);
    _numberController.removeListener(_onFieldChanged);
    _neighborhoodController.removeListener(_onFieldChanged);
    _cityController.removeListener(_onFieldChanged);
    _stateController.removeListener(_onFieldChanged);
    _zipCodeController.removeListener(_onFieldChanged);
    _zipCodeController.removeListener(_onCepChanged);
    _totalAreaController.removeListener(_onFieldChanged);
    _builtAreaController.removeListener(_onFieldChanged);
    _ownerNameController.removeListener(_onFieldChanged);
    _ownerEmailController.removeListener(_onFieldChanged);
    _ownerPhoneController.removeListener(_onFieldChanged);
    _ownerDocumentController.removeListener(_onFieldChanged);
    _ownerAddressController.removeListener(_onFieldChanged);
    _sectorController.removeListener(_onFieldChanged);
    _internalNotesController.removeListener(_onFieldChanged);
    _suitesController.removeListener(_onFieldChanged);

    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _internalNotesController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _sectorController.dispose();
    _totalAreaController.dispose();
    _builtAreaController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _parkingSpacesController.dispose();
    _suitesController.dispose();
    _salePriceController.dispose();
    _rentPriceController.dispose();
    _condominiumFeeController.dispose();
    _iptuController.dispose();
    _minSalePriceController.dispose();
    _minRentPriceController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPhoneController.dispose();
    _ownerDocumentController.dispose();
    _ownerAddressController.dispose();
    _anonymousAutoSaveTimer?.cancel();
    // Flush final do rascunho anônimo se houver mudanças pendentes — paridade
    // com o `useEffect` cleanup do web. Best-effort; se falhar, ignora.
    if (widget.propertyId == null) {
      _flushAnonymousAutoSave();
    }
    super.dispose();
  }

  Future<void> _loadProperty() async {
    if (widget.propertyId == null) return;

    setState(() {
      _isLoadingProperty = true;
    });

    try {
      final response = await _propertyService.getPropertyById(
        widget.propertyId!,
      );

      if (mounted && response.success && response.data != null) {
        final property = response.data!;
        _populateForm(property);
      }
    } catch (e) {
      debugPrint('Erro ao carregar propriedade: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProperty = false;
        });
      }
    }
  }

  void _populateForm(Property property) {
    _titleController.text = property.title;
    _descriptionController.text = property.description;
    _selectedType = property.type;

    _streetController.text = property.street;
    _numberController.text = property.number;
    _complementController.text = property.complement ?? '';
    _neighborhoodController.text = property.neighborhood;
    _cityController.text = property.city;
    _stateController.text = property.state;
    _zipCodeController.text = property.zipCode;

    _sectorController.text = property.sector ?? '';
    _internalNotesController.text = property.internalNotes ?? '';
    _selectedTeamId = property.teamId;
    _selectedCondominiumId = property.condominiumId;
    _selectedEmpreendimentoId = property.empreendimentoId;
    // Inferir o modo de endereço a partir dos vínculos existentes — paridade
    // `CreatePropertyPage.tsx` (`isCondominium = !!property.condominiumId`).
    final hasCondo = (property.condominiumId ?? '').trim().isNotEmpty;
    final hasEmp = (property.empreendimentoId ?? '').trim().isNotEmpty;
    _addressMode = hasCondo
        ? PropertyCreationAddressMode.condominium
        : hasEmp
            ? PropertyCreationAddressMode.empreendimento
            : PropertyCreationAddressMode.standalone;
    _loadedCapturedById =
        property.capturedById ?? property.capturedBy?.id;

    _totalAreaController.text = property.totalArea > 0
        ? property.totalArea.toString()
        : '';
    _builtAreaController.text = property.builtArea?.toString() ?? '';
    _bedroomsController.text = property.bedrooms?.toString() ?? '';
    _bathroomsController.text = property.bathrooms?.toString() ?? '';
    _parkingSpacesController.text = property.parkingSpaces?.toString() ?? '';
    _selectedFeatures.clear();
    _selectedFeatures.addAll(property.features);

    _suitesController.text = property.suites?.toString() ?? '';

    _salePriceController.text = property.salePrice != null
        ? Masks.money((property.salePrice! * 100).toStringAsFixed(0))
        : '';
    _rentPriceController.text = property.rentPrice != null
        ? Masks.money((property.rentPrice! * 100).toStringAsFixed(0))
        : '';
    _condominiumFeeController.text = property.condominiumFee != null
        ? Masks.money((property.condominiumFee! * 100).toStringAsFixed(0))
        : '';
    _iptuController.text = property.iptu != null
        ? Masks.money((property.iptu! * 100).toStringAsFixed(0))
        : '';
    _acceptsNegotiation = property.acceptsNegotiation ?? false;
    _minSalePriceController.text = property.minSalePrice != null
        ? Masks.money((property.minSalePrice! * 100).toStringAsFixed(0))
        : '';
    _minRentPriceController.text = property.minRentPrice != null
        ? Masks.money((property.minRentPrice! * 100).toStringAsFixed(0))
        : '';
    _offerBelowMinSaleAction = property.offerBelowMinSaleAction;
    _offerBelowMinRentAction = property.offerBelowMinRentAction;

    // Proprietário
    if (property.owner != null) {
      _ownerNameController.text = property.owner!.name ?? '';
      _ownerEmailController.text = property.owner!.email ?? '';
      _ownerPhoneController.text = property.owner!.phone ?? '';
      _ownerDocumentController.text = property.owner!.document ?? '';
      _ownerAddressController.text = property.owner!.address ?? '';
    }

    _listingStatusIsDraft = property.status == PropertyStatus.draft;
    _publishToSite = property.isAvailableForSite ?? false;
    _isFeatured = property.isFeatured;
    _loadedPropertyStatus = property.status.value;
    _loadedPropertyIsAvailableForSite = property.isAvailableForSite ?? false;
    final imgList = property.images;
    final fromList = imgList == null
        ? 0
        : imgList.where((img) => img.url.trim().isNotEmpty).length;
    _serverImageCountAtLoad =
        property.imageCount ?? (fromList > 0 ? fromList : 0);

    if (property.images != null) {
      _uploadedImages.clear();
      // Converter PropertyImage para GalleryImage (aproximação)
      // Em produção, você pode buscar as imagens completas via GalleryService
    }
    _scheduleLoadPickerListsIfNeeded();
  }

  Future<void> _searchCep() async {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CEP deve ter 8 dígitos')));
      return;
    }

    try {
      final address = await _cepService.searchCep(cep);
      if (address != null && mounted) {
        setState(() {
          _streetController.text = address.street ?? '';
          _neighborhoodController.text = address.neighborhood ?? '';
          _cityController.text = address.city ?? '';
          _stateController.text = address.state ?? '';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('CEP encontrado!')));
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('CEP não encontrado')));
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erro ao buscar CEP')));
      }
    }
  }

  Future<void> _pickImages() async {
    // Mostrar opções: tirar foto ou selecionar da galeria
    final option = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar Foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Selecionar da Galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );

    if (option == null) return;

    try {
      if (option == ImageSource.camera) {
        // Tirar foto
        final XFile? photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo != null && mounted) {
          // Crop premium 1:1 — única opção pra imóvel.
          //
          // Comportamento ajustado: se o user CANCELAR o crop, a foto
          // original NÃO é adicionada (antes adicionávamos mesmo assim,
          // o que burlava o lock 1:1). Agora ou ele recorta em quadrado
          // ou nada vai pra fila — alinhado com o que a fila de
          // aprovação espera.
          final croppedFile = await ImageCropHelper.cropImageSquare(
            context: context,
            imagePath: photo.path,
          );
          if (croppedFile != null && mounted) {
            setState(() => _selectedImages.add(croppedFile));
          }
        }
      } else {
        // Selecionar múltiplas imagens da galeria
        final List<XFile> images = await _imagePicker.pickMultiImage(
          imageQuality: 85,
        );
        if (images.isNotEmpty && mounted) {
          for (final xFile in images) {
            if (!mounted) break;
            final croppedFile = await ImageCropHelper.cropImageSquare(
              context: context,
              imagePath: xFile.path,
            );
            if (croppedFile != null && mounted) {
              setState(() => _selectedImages.add(croppedFile));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagens: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagens: $e'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _uploadImages(String propertyId) async {
    if (_selectedImages.isEmpty) return;

    setState(() {
      _isUploadingImages = true;
    });

    try {
      final response = await _galleryService.uploadImages(
        propertyId: propertyId,
        files: _selectedImages,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _uploadedImages.addAll(response.data!);
            _selectedImages.clear();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ?? 'Erro ao fazer upload das imagens',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao fazer upload das imagens')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImages = false;
        });
      }
    }
  }

  Future<void> _generateDescription() async {
    if (_totalAreaController.text.trim().isEmpty ||
        _cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha pelo menos: tipo, cidade e área total'),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingDescription = true;
    });

    try {
      final request = GenerateDescriptionRequest(
        type: _selectedType.value,
        city: _cityController.text.trim(),
        neighborhood: _neighborhoodController.text.trim().isEmpty
            ? null
            : _neighborhoodController.text.trim(),
        totalArea: double.tryParse(_totalAreaController.text) ?? 0.0,
        builtArea: _builtAreaController.text.trim().isEmpty
            ? null
            : double.tryParse(_builtAreaController.text),
        bedrooms: _bedroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_bedroomsController.text),
        bathrooms: _bathroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_bathroomsController.text),
        parkingSpaces: _parkingSpacesController.text.trim().isEmpty
            ? null
            : int.tryParse(_parkingSpacesController.text),
        salePrice: _salePriceController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_salePriceController.text) / 100.0,
        rentPrice: _rentPriceController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_rentPriceController.text) / 100.0,
        condominiumFee: _condominiumFeeController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_condominiumFeeController.text) / 100.0,
        iptu: _iptuController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_iptuController.text) / 100.0,
        features: _selectedFeatures.isEmpty ? null : _selectedFeatures,
      );

      final response = await _aiService.generatePropertyDescription(request);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _titleController.text = response.data!.title;
            _descriptionController.text = response.data!.description;
            _generatedVariants.add(response.data!);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Descrição gerada com sucesso!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao gerar descrição'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao gerar descrição: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao gerar descrição')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingDescription = false;
        });
      }
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0: // Etapa 1: Informações Básicas
        // Título e descrição só são obrigatórios se a IA estiver desativada
        if (!_autoGenerateOnReview) {
          if (_titleController.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Por favor, preencha o título ou ative a geração automática com IA',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
          if (_titleController.text.trim().length < 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Título deve ter pelo menos 3 caracteres'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
          if (_descriptionController.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Por favor, preencha a descrição ou ative a geração automática com IA',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
          if (_descriptionController.text.trim().length < 10) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Descrição deve ter pelo menos 10 caracteres',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
          if (_titleController.text.trim().length > 255) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Título não pode ultrapassar 255 caracteres'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
          if (_descriptionController.text.trim().length > 5000) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Descrição não pode ultrapassar 5000 caracteres'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        } else {
          // Geração com IA na revisão: valida apenas trechos já preenchidos
          final t = _titleController.text.trim();
          if (t.isNotEmpty) {
            if (t.length < 3 || t.length > 255) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Título deve ter entre 3 e 255 caracteres',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
              return false;
            }
          }
          final d = _descriptionController.text.trim();
          if (d.isNotEmpty) {
            if (d.length < 10 || d.length > 5000) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                      'Descrição deve ter entre 10 e 5000 caracteres',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
              return false;
            }
          }
        }
        return true;

      case 1: // Etapa 2: Localização
        if (_streetController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha a rua'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_numberController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha o número'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_neighborhoodController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha o bairro'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_cityController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha a cidade'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_cityController.text.trim().length < 2 ||
            _cityController.text.trim().length > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Cidade deve ter entre 2 e 100 caracteres',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_neighborhoodController.text.trim().length < 2 ||
            _neighborhoodController.text.trim().length > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Bairro deve ter entre 2 e 100 caracteres',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_stateController.text.trim().isEmpty ||
            _stateController.text.trim().length != 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Por favor, preencha o estado (UF) com 2 letras',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        final stateForUf = _stateController.text.trim().toUpperCase();
        if (!RegExp(r'^[A-Z]{2}$').hasMatch(stateForUf)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'UF inválido: use 2 letras (ex.: SP, RJ)',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        final cep = _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (cep.isEmpty || cep.length != 8) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Por favor, preencha um CEP válido (8 dígitos)',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        return true;

      case 2: // Etapa 3: Características
        if (_totalAreaController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha a área total'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        final totalArea = double.tryParse(_totalAreaController.text);
        if (totalArea == null || totalArea <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Área total deve ser maior que zero'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (totalArea >= 1000000) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Área total deve ser menor que 1.000.000 m²'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        // Validar área construída se preenchida
        if (_builtAreaController.text.trim().isNotEmpty) {
          final builtArea = double.tryParse(_builtAreaController.text);
          if (builtArea != null) {
            if (builtArea <= 0 || builtArea >= 1000000) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                      'Área construída inválida (verifique valor e máximo permitido)',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
              return false;
            }
            if (builtArea > totalArea) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Área construída não pode ser maior que área total',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
              return false;
            }
          }
        }
        if (_bedroomsController.text.trim().isNotEmpty) {
          final bedrooms = int.tryParse(_bedroomsController.text);
          if (bedrooms == null || bedrooms < 0 || bedrooms >= 50) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    const Text('Quartos: informe um número entre 0 e 49'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        }
        if (_bathroomsController.text.trim().isNotEmpty) {
          final bathrooms = int.tryParse(_bathroomsController.text);
          if (bathrooms == null || bathrooms < 0 || bathrooms >= 20) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Banheiros: informe um número entre 0 e 19'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        }
        if (_parkingSpacesController.text.trim().isNotEmpty) {
          final parking = int.tryParse(_parkingSpacesController.text);
          if (parking == null || parking < 0 || parking >= 20) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Vagas: informe um número entre 0 e 19'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        }
        return true;

      case 3: // Etapa 4: Valores
        // Se aceita negociação, deve ter preço mínimo de venda OU aluguel
        if (_acceptsNegotiation) {
          final hasSalePrice = _salePriceController.text.trim().isNotEmpty;
          final hasRentPrice = _rentPriceController.text.trim().isNotEmpty;
          final hasMinSalePrice = _minSalePriceController.text
              .trim()
              .isNotEmpty;
          final hasMinRentPrice = _minRentPriceController.text
              .trim()
              .isNotEmpty;

          if (hasSalePrice && !hasMinSalePrice) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Ao aceitar negociação, é obrigatório informar o preço mínimo de venda quando há preço de venda',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }

          if (hasRentPrice && !hasMinRentPrice) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Ao aceitar negociação, é obrigatório informar o preço mínimo de aluguel quando há preço de aluguel',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        }
        return true;

      case 4: // Etapa 5: Galeria (paridade CRM web: mínimo 2, máximo 50).
        final totalImages = _totalSelectableImageCount();
        if (totalImages < _kMinGalleryImagesWeb) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'É necessário adicionar no mínimo $_kMinGalleryImagesWeb imagens. '
                'Atualmente: $totalImages.',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (totalImages > _kMaxGalleryImagesWeb) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Limite de $_kMaxGalleryImagesWeb imagens. Atualmente: $totalImages.',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        return true;

      case 5: // Etapa 6: Clientes e Proprietário
        // Paridade `handleCreateProperty` web: apenas nome + telefone obrigatórios.
        if (_ownerNameController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Por favor, preencha o nome do proprietário'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        final emailTrim = _ownerEmailController.text.trim();
        if (emailTrim.isNotEmpty) {
          final emailRegex = RegExp(
            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
          );
          if (emailTrim.length > 255 || !emailRegex.hasMatch(emailTrim)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    const Text('Se informado, o e-mail do proprietário deve ser válido'),
                backgroundColor: AppColors.status.error,
              ),
            );
            return false;
          }
        }
        final phoneDigits =
            _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '');
        if (phoneDigits.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Por favor, preencha o telefone do proprietário',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (phoneDigits.length < 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Telefone do proprietário: informe pelo menos 10 dígitos',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        final docDig =
            _ownerDocumentController.text.replaceAll(RegExp(r'\D'), '');
        if (docDig.isNotEmpty && docDig.length < 11) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Se informado, CPF/CNPJ deve ter ao menos 11 dígitos'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        return true;

      case 6: // Etapa 7: Revisão
        // Validar título e descrição na revisão (sempre obrigatórios na revisão)
        if (_titleController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Por favor, preencha o título ou gere com IA',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_titleController.text.trim().length < 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Título deve ter pelo menos 3 caracteres'),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_descriptionController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Por favor, preencha a descrição ou gere com IA',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        if (_descriptionController.text.trim().length < 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Descrição deve ter pelo menos 10 caracteres',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          return false;
        }
        return true;

      default:
        return true;
    }
  }

  void _nextStep() {
    // Validar etapa atual antes de avançar
    if (!_validateCurrentStep()) {
      return; // Não avança se houver erro
    }

    if (_currentStep < _totalSteps - 1) {
      final nextStep = _currentStep + 1;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _setStateAndPersist(() {
        _currentStep = nextStep;
      });

      // Se chegou na etapa de revisão e auto-geração está ativada, gerar automaticamente
      if (nextStep == 6 &&
          _autoGenerateOnReview &&
          !_hasAutoGeneratedOnReview) {
        _autoGenerateDescriptionOnReview();
      }
    }
  }

  Future<void> _autoGenerateDescriptionOnReview() async {
    // Valida campos mínimos
    if (_totalAreaController.text.trim().isEmpty ||
        _cityController.text.trim().isEmpty) {
      return; // Não gera se não tiver dados mínimos
    }

    setState(() {
      _hasAutoGeneratedOnReview = true;
      _isGeneratingDescription = true;
    });

    try {
      final request = GenerateDescriptionRequest(
        type: _selectedType.value,
        city: _cityController.text.trim(),
        neighborhood: _neighborhoodController.text.trim().isEmpty
            ? null
            : _neighborhoodController.text.trim(),
        totalArea: double.tryParse(_totalAreaController.text) ?? 0.0,
        builtArea: _builtAreaController.text.trim().isEmpty
            ? null
            : double.tryParse(_builtAreaController.text),
        bedrooms: _bedroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_bedroomsController.text),
        bathrooms: _bathroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_bathroomsController.text),
        parkingSpaces: _parkingSpacesController.text.trim().isEmpty
            ? null
            : int.tryParse(_parkingSpacesController.text),
        salePrice: _salePriceController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_salePriceController.text) / 100.0,
        rentPrice: _rentPriceController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_rentPriceController.text) / 100.0,
        condominiumFee: _condominiumFeeController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_condominiumFeeController.text) / 100.0,
        iptu: _iptuController.text.trim().isEmpty
            ? null
            : Masks.unmaskMoney(_iptuController.text) / 100.0,
        features: _selectedFeatures.isEmpty ? null : _selectedFeatures,
      );

      final response = await _aiService.generatePropertyDescription(request);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            // Só preenche se os campos estiverem vazios
            if (_titleController.text.trim().isEmpty) {
              _titleController.text = response.data!.title;
            }
            if (_descriptionController.text.trim().isEmpty) {
              _descriptionController.text = response.data!.description;
            }
            _generatedVariants.add(response.data!);
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao gerar descrição automaticamente: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingDescription = false;
        });
      }
    }
  }

  Map<String, dynamic> _freezeFormState() {
    return {
      'wizardStep': _currentStep,
      'addressMode': _addressMode.value,
      'addressLinkedEntityName': _addressLinkedEntityName,
      'title': _titleController.text,
      'description': _descriptionController.text,
      'street': _streetController.text,
      'number': _numberController.text,
      'complement': _complementController.text,
      'neighborhood': _neighborhoodController.text,
      'city': _cityController.text,
      'state': _stateController.text,
      'zipCode': _zipCodeController.text,
      'totalArea': _totalAreaController.text,
      'builtArea': _builtAreaController.text,
      'bedrooms': _bedroomsController.text,
      'bathrooms': _bathroomsController.text,
      'parkingSpaces': _parkingSpacesController.text,
      'suites': _suitesController.text,
      'sector': _sectorController.text,
      'internalNotes': _internalNotesController.text,
      'selectedTeamId': _selectedTeamId,
      'selectedCondominiumId': _selectedCondominiumId,
      'selectedEmpreendimentoId': _selectedEmpreendimentoId,
      'salePrice': _salePriceController.text,
      'rentPrice': _rentPriceController.text,
      'condominiumFee': _condominiumFeeController.text,
      'iptu': _iptuController.text,
      'minSalePrice': _minSalePriceController.text,
      'minRentPrice': _minRentPriceController.text,
      'offerBelowMinSaleAction': _offerBelowMinSaleAction,
      'offerBelowMinRentAction': _offerBelowMinRentAction,
      'ownerName': _ownerNameController.text,
      'ownerEmail': _ownerEmailController.text,
      'ownerPhone': _ownerPhoneController.text,
      'ownerDocument': _ownerDocumentController.text,
      'ownerAddress': _ownerAddressController.text,
      'type': _selectedType.value,
      'selectedFeatures': List<String>.from(_selectedFeatures),
      'selectedClientIds': List<String>.from(_selectedClientIds),
      'acceptsNegotiation': _acceptsNegotiation,
      'publishToSite': _publishToSite,
      'listingStatusIsDraft': _listingStatusIsDraft,
      'isFeatured': _isFeatured,
      'autoGenerateOnReview': _autoGenerateOnReview,
      'hasAutoGeneratedOnReview': _hasAutoGeneratedOnReview,
      'aiVariants': _generatedVariants
          .map(
            (v) => {
              'title': v.title,
              'description': v.description,
              'highlights': v.highlights,
            },
          )
          .toList(),
    };
  }

  void _applyFrozenFormState(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return;

    String s(String key) => raw[key]?.toString() ?? '';

    void setIfPresent(TextEditingController c, String key) {
      final v = s(key);
      if (v.isNotEmpty) c.text = v;
    }

    setIfPresent(_titleController, 'title');
    setIfPresent(_descriptionController, 'description');
    setIfPresent(_streetController, 'street');
    setIfPresent(_numberController, 'number');
    setIfPresent(_complementController, 'complement');
    setIfPresent(_neighborhoodController, 'neighborhood');
    setIfPresent(_cityController, 'city');
    setIfPresent(_stateController, 'state');
    setIfPresent(_zipCodeController, 'zipCode');
    setIfPresent(_sectorController, 'sector');
    setIfPresent(_internalNotesController, 'internalNotes');
    setIfPresent(_totalAreaController, 'totalArea');
    setIfPresent(_builtAreaController, 'builtArea');
    setIfPresent(_bedroomsController, 'bedrooms');
    setIfPresent(_bathroomsController, 'bathrooms');
    setIfPresent(_parkingSpacesController, 'parkingSpaces');
    setIfPresent(_suitesController, 'suites');
    setIfPresent(_salePriceController, 'salePrice');
    setIfPresent(_rentPriceController, 'rentPrice');
    setIfPresent(_condominiumFeeController, 'condominiumFee');
    setIfPresent(_iptuController, 'iptu');
    setIfPresent(_minSalePriceController, 'minSalePrice');
    setIfPresent(_minRentPriceController, 'minRentPrice');
    setIfPresent(_ownerNameController, 'ownerName');
    setIfPresent(_ownerEmailController, 'ownerEmail');
    setIfPresent(_ownerPhoneController, 'ownerPhone');
    setIfPresent(_ownerDocumentController, 'ownerDocument');
    setIfPresent(_ownerAddressController, 'ownerAddress');

    final tp = PropertyType.fromString(raw['type']?.toString());
    if (tp != null) _selectedType = tp;

    _selectedFeatures.clear();
    final feats = raw['selectedFeatures'];
    if (feats is List) {
      _selectedFeatures.addAll(feats.map((e) => e.toString()));
    }

    _selectedClientIds.clear();
    final cid = raw['selectedClientIds'];
    if (cid is List) {
      _selectedClientIds.addAll(cid.map((e) => e.toString()));
    }

    _acceptsNegotiation = raw['acceptsNegotiation'] == true;
    _publishToSite = raw['publishToSite'] == true;
    _listingStatusIsDraft = raw['listingStatusIsDraft'] != false;
    _isFeatured = raw['isFeatured'] == true;
    _autoGenerateOnReview = raw['autoGenerateOnReview'] != false;
    _hasAutoGeneratedOnReview = raw['hasAutoGeneratedOnReview'] == true;

    final os = raw['offerBelowMinSaleAction']?.toString();
    if (os != null && os.isNotEmpty) _offerBelowMinSaleAction = os;

    final or = raw['offerBelowMinRentAction']?.toString();
    if (or != null && or.isNotEmpty) _offerBelowMinRentAction = or;

    _selectedTeamId = raw['selectedTeamId']?.toString();
    _selectedCondominiumId = raw['selectedCondominiumId']?.toString();
    _selectedEmpreendimentoId = raw['selectedEmpreendimentoId']?.toString();

    _addressMode = PropertyCreationAddressModeX.fromValue(
      raw['addressMode']?.toString(),
    );
    final linkedName = raw['addressLinkedEntityName']?.toString();
    if (linkedName != null && linkedName.isNotEmpty) {
      _addressLinkedEntityName = linkedName;
    }
    final restoredStep = raw['wizardStep'];
    if (restoredStep is int) {
      _currentStep = restoredStep.clamp(0, _totalSteps - 1);
    } else if (restoredStep is num) {
      _currentStep = restoredStep.toInt().clamp(0, _totalSteps - 1);
    }

    _generatedVariants.clear();
    final variants = raw['aiVariants'];
    if (variants is List) {
      for (final v in variants) {
        if (v is Map) {
          try {
            _generatedVariants.add(
              GeneratedDescription.fromJson(v.cast<String, dynamic>()),
            );
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _loadLocalDraft(String id) async {
    if (_isHydratingLocalDraft || widget.propertyId != null) return;
    _isHydratingLocalDraft = true;
    try {
      final draft = await _draftStorage.getById(id);
      if (!mounted || draft == null) {
        _isHydratingLocalDraft = false;
        return;
      }
      _uploadedImages.clear();
      _selectedImages.clear();

      _applyFrozenFormState(draft.formJson);

      for (final path in draft.imagePaths) {
        try {
          final f = File(path);
          if (f.existsSync()) {
            _selectedImages.add(f);
          }
        } catch (_) {}
      }

      final step = draft.wizardStep.clamp(0, _totalSteps - 1);
      setState(() {
        _activeLocalDraftId = draft.id;
        _activeLocalDraftDisplayTitle = draft.displayTitle;
        _currentStep = step;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageController.jumpToPage(step);
      });
    } catch (e, st) {
      debugPrint('Erro ao carregar rascunho local: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Não foi possível abrir este rascunho. Ele pode ter sido removido.',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      _isHydratingLocalDraft = false;
    }
  }

  Future<void> _persistLocalDraftToDevice(String displayTitle) async {
    if (widget.propertyId != null) return;
    final trimmed = displayTitle.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Informe um título para o rascunho.'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final companyId =
          (await SecureStorageService.instance.getCompanyId()) ?? '';
      // Sincroniza primeiro com o backend (campos do form + wizard step) para
      // obter um id estável de servidor — só então copiamos as imagens
      // para a pasta nomeada por esse id. Imagens permanecem locais.
      final draftToSave = PropertyLocalDraft(
        id: _activeLocalDraftId ?? '',
        displayTitle: trimmed,
        companyId: companyId,
        updatedAt: DateTime.now(),
        wizardStep: _currentStep.clamp(0, _totalSteps - 1),
        formJson: _freezeFormState(),
        imagePaths: const [],
      );

      final saved = await _draftStorage.save(draftToSave);

      List<String> paths = const [];
      if (_selectedImages.isNotEmpty) {
        paths = await _draftStorage.copyImagesToDraftFolder(
          draftId: saved.id,
          sources: List<File>.from(_selectedImages),
        );
        await _draftStorage.setLocalImagePaths(saved.id, paths);
      } else {
        await _draftStorage.setLocalImagePaths(saved.id, const []);
      }

      if (mounted) {
        setState(() {
          _activeLocalDraftId = saved.id;
          _activeLocalDraftDisplayTitle = trimmed;
          _selectedImages.clear();
          for (final p in paths) {
            try {
              final f = File(p);
              if (f.existsSync()) _selectedImages.add(f);
            } catch (_) {}
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Rascunho «$trimmed» sincronizado com a sua conta.'),
            backgroundColor: AppColors.status.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar rascunho local: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao guardar rascunho: $e'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSaveLocalDraftSheet() {
    if (widget.propertyId != null) return;

    final initial = (_activeLocalDraftDisplayTitle ??
            _titleController.text.trim())
        .trim();
    final tc = TextEditingController(
      text: initial.isEmpty
          ? 'Rascunho ${DateFormat("dd/MM · HH:mm", 'pt_BR').format(DateTime.now())}'
          : initial,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = isDark ? const Color(0xFF8B5CF6) : const Color(0xFF6366F1);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom +
                MediaQuery.paddingOf(ctx).bottom +
                8,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color:
                      Colors.white.withValues(alpha: isDark ? 0.14 : 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF25244A),
                            const Color(0xFF1A1A2E),
                          ]
                        : [
                            Colors.white,
                            const Color(0xFFF5F3FF),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: brand.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: brand.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.bookmark_add_rounded,
                            color: brand,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rascunho local',
                                style: Theme.of(ctx).textTheme.titleLarge
                                    ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fica neste aparelho. Você pode continuar depois pela lista de rascunhos.',
                                style: Theme.of(ctx).textTheme.bodySmall
                                    ?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(ctx),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: tc,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Título do rascunho',
                        hintText: 'Ex.: Casa Zona Sul — falta preço',
                        filled: true,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final t = tc.text.trim();
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              await _persistLocalDraftToDevice(t);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text(
                        'Guardar rascunho',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _saveProperty(saveAsDraft: true);
                            },
                      icon: Icon(Icons.cloud_upload_outlined, color: brand),
                      label: Text(
                        'Enviar rascunho ao CRM (servidor)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: brand,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'O servidor exige os mesmos dados mínimos do cadastro web.',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(ctx),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(tc.dispose);
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _setStateAndPersist(() {
        _currentStep--;
      });
    }
  }

  String _resolvedApiStatus(bool saveAsDraft) {
    if (saveAsDraft) return 'draft';
    final isEditing = widget.propertyId != null;
    final canPickListing = _approvalSettingsLoaded &&
        !_requireApprovalToBeAvailable &&
        !_requireOwnerAuthorizationToBeAvailable;
    if (isEditing && !canPickListing) {
      return _loadedPropertyStatus ?? 'draft';
    }
    if (_requireApprovalToBeAvailable ||
        _requireOwnerAuthorizationToBeAvailable) {
      return 'available';
    }
    return _listingStatusIsDraft ? 'draft' : 'available';
  }

  /// Verifica regras de publicação no site. Retorna `null` se OK ou um
  /// `_StepValidationFailure` apontando para o step exato do problema —
  /// galeria insuficiente vai pro Step 4, conflitos de status/rascunho vão
  /// pro Step 6 (Revisão final, onde os toggles ficam).
  _StepValidationFailure? _checkPublicationRules({
    required bool saveAsDraft,
    required String resolvedStatus,
  }) {
    if (!_publishToSite) return null;

    if (saveAsDraft) {
      return const _StepValidationFailure(
        step: 6,
        message:
            'Desative «Publicar no site» ao salvar como rascunho (regra igual ao sistema web).',
      );
    }

    final imgCount = _totalSelectableImageCount();
    if (imgCount < _kMinGalleryImagesWeb || imgCount > _kMaxGalleryImagesWeb) {
      return _StepValidationFailure(
        step: 4,
        message:
            'Publicação no site exige entre $_kMinGalleryImagesWeb e $_kMaxGalleryImagesWeb '
            'imagens (atual: $imgCount).',
      );
    }

    // Paridade CreatePropertyPage web: só «Disponível» bloqueia se não há
    // `requireApprovalToBeAvailable` (linha ~3204 do CreatePropertyPage.tsx).
    final needsAvailableResolved = !_requireApprovalToBeAvailable;
    if (needsAvailableResolved && resolvedStatus != 'available') {
      return const _StepValidationFailure(
        step: 6,
        message:
            'Apenas imóveis com status «Disponível» podem ser publicados no site '
            '(quando a empresa não exige apenas a fila de aprovação).',
      );
    }

    return null;
  }

  /// Mapa `key` (do backend) → índice do step onde ele é editado.
  /// Usado para roteamento automático ao primeiro erro de validação,
  /// inclusive nos campos retornados por `configurableFieldsErrorPt`.
  static const Map<String, int> _fieldStepMap = {
    // Step 0 — Informações básicas
    'type': 0,
    'title': 0,
    'description': 0,
    'teamId': 0,
    // Step 1 — Localização
    'zipCode': 1,
    'street': 1,
    'number': 1,
    'complement': 1,
    'neighborhood': 1,
    'sector': 1,
    'city': 1,
    'state': 1,
    'condominiumId': 1,
    'empreendimentoId': 1,
    // Step 2 — Medidas e detalhes
    'totalArea': 2,
    'builtArea': 2,
    'bedrooms': 2,
    'suites': 2,
    'bathrooms': 2,
    'parkingSpaces': 2,
    'features': 2,
    // Step 3 — Valores
    'salePrice': 3,
    'rentPrice': 3,
    'condominiumFee': 3,
    'iptu': 3,
    // Step 5 — Proprietário (Step 4 é Galeria)
    'ownerName': 5,
    'ownerEmail': 5,
    'ownerPhone': 5,
    'ownerDocument': 5,
    'capturedById': 5,
    'capturedByIds': 5,
    'internalNotes': 5,
  };

  /// Roda as validações de cada step em ordem e retorna o primeiro erro
  /// encontrado (ou `null` se tudo OK). É a fonte da verdade do "saltar
  /// até o problema" — não depende dos `validator:` dos `TextFormField`,
  /// ao contrário do `_formKey.currentState.validate()`, que só dispara
  /// validações dos widgets atualmente montados na árvore.
  _StepValidationFailure? _findFirstStepValidationError({
    required bool saveAsDraft,
  }) {
    // ============================ Step 0 ============================
    if (!_autoGenerateOnReview) {
      final t = _titleController.text.trim();
      if (t.isEmpty) {
        return const _StepValidationFailure(
          step: 0,
          message: 'Informe o título do anúncio.',
        );
      }
      if (t.length < 3) {
        return const _StepValidationFailure(
          step: 0,
          message: 'O título deve ter pelo menos 3 caracteres.',
        );
      }
      if (t.length > 255) {
        return const _StepValidationFailure(
          step: 0,
          message: 'O título deve ter no máximo 255 caracteres.',
        );
      }
      final d = _descriptionController.text.trim();
      if (d.isEmpty) {
        return const _StepValidationFailure(
          step: 0,
          message: 'Informe a descrição do imóvel.',
        );
      }
      if (d.length < 10) {
        return const _StepValidationFailure(
          step: 0,
          message: 'A descrição deve ter pelo menos 10 caracteres.',
        );
      }
      if (d.length > 5000) {
        return const _StepValidationFailure(
          step: 0,
          message: 'A descrição deve ter no máximo 5000 caracteres.',
        );
      }
    }
    if (_formRequiredKeys.contains('teamId') &&
        (_selectedTeamId ?? '').trim().isEmpty) {
      return const _StepValidationFailure(
        step: 0,
        message: 'Selecione a equipe responsável pelo imóvel.',
      );
    }

    // ============================ Step 1 ============================
    final zipDigits =
        _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (zipDigits.isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe o CEP do imóvel.',
      );
    }
    if (zipDigits.length != 8) {
      return const _StepValidationFailure(
        step: 1,
        message: 'O CEP deve ter 8 dígitos.',
      );
    }
    final street = _streetController.text.trim();
    if (street.isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe a rua / logradouro.',
      );
    }
    if (street.length < 2) {
      return const _StepValidationFailure(
        step: 1,
        message: 'A rua deve ter pelo menos 2 caracteres.',
      );
    }
    if (_numberController.text.trim().isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe o número do endereço.',
      );
    }
    if (_formRequiredKeys.contains('complement') &&
        _complementController.text.trim().isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Complemento obrigatório (configuração da empresa).',
      );
    }
    final neighborhood = _neighborhoodController.text.trim();
    if (neighborhood.isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe o bairro.',
      );
    }
    if (neighborhood.length < 2) {
      return const _StepValidationFailure(
        step: 1,
        message: 'O bairro deve ter pelo menos 2 caracteres.',
      );
    }
    if (neighborhood.length > 100) {
      return const _StepValidationFailure(
        step: 1,
        message: 'O bairro deve ter no máximo 100 caracteres.',
      );
    }
    if (_formRequiredKeys.contains('sector') &&
        _sectorController.text.trim().isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Setor obrigatório (configuração da empresa).',
      );
    }
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe a cidade.',
      );
    }
    if (city.length < 2) {
      return const _StepValidationFailure(
        step: 1,
        message: 'A cidade deve ter pelo menos 2 caracteres.',
      );
    }
    if (city.length > 100) {
      return const _StepValidationFailure(
        step: 1,
        message: 'A cidade deve ter no máximo 100 caracteres.',
      );
    }
    final state = _stateController.text.trim().toUpperCase();
    if (state.isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Informe a UF (estado).',
      );
    }
    if (state.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(state)) {
      return const _StepValidationFailure(
        step: 1,
        message: 'A UF deve ter 2 letras maiúsculas (ex.: SP, RJ).',
      );
    }
    // Vínculo a condomínio/empreendimento só é obrigatório quando o usuário
    // optou pelo respectivo modo de endereço — paridade `CreatePropertyPage.tsx`
    // linhas 2522-2523 (`if (key === 'condominiumId') return !!formData.isCondominium`).
    // O `_formRequiredKeys` da empresa NÃO conta para forçar esses IDs;
    // o backend pode rejeitar com 400 nesse caso, mas isso é tratado como
    // erro de config e mostrado de forma amigável (sem deslogar o usuário).
    if (_addressMode == PropertyCreationAddressMode.condominium &&
        (_selectedCondominiumId ?? '').trim().isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Selecione um condomínio para vincular o imóvel.',
      );
    }
    if (_addressMode == PropertyCreationAddressMode.empreendimento &&
        (_selectedEmpreendimentoId ?? '').trim().isEmpty) {
      return const _StepValidationFailure(
        step: 1,
        message: 'Selecione um empreendimento para vincular o imóvel.',
      );
    }
    // Regra de negócio: apartamentos sempre precisam estar vinculados a um
    // condomínio. Se o usuário voltou e mudou o tipo no wizard, mantemos a
    // checagem aqui (no setup modal o "Endereço próprio" já fica desabilitado).
    if (_selectedType == PropertyType.apartment &&
        _addressMode == PropertyCreationAddressMode.standalone) {
      return const _StepValidationFailure(
        step: 1,
        message:
            'Apartamentos precisam estar vinculados a um condomínio. Toque em "Alterar" para escolher um.',
      );
    }

    // ============================ Step 2 ============================
    final totalArea = _parseBrazilianAreaToNumber(_totalAreaController.text);
    if (totalArea == null || totalArea <= 0) {
      return const _StepValidationFailure(
        step: 2,
        message: 'Informe a área total do imóvel.',
      );
    }
    if (totalArea >= 1000000) {
      return const _StepValidationFailure(
        step: 2,
        message: 'A área total deve ser menor que 1.000.000 m².',
      );
    }
    if (_formRequiredKeys.contains('features') && _selectedFeatures.isEmpty) {
      return const _StepValidationFailure(
        step: 2,
        message:
            'Selecione pelo menos uma característica (configuração da empresa).',
      );
    }

    // ============================ Step 3 ============================
    final saleText = _salePriceController.text.trim();
    if (saleText.isNotEmpty) {
      final p = Masks.unmaskMoney(saleText) / 100.0;
      if (p <= 0) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Preço de venda deve ser positivo.',
        );
      }
      if (p >= 1000000000) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Preço de venda deve ser menor que R\$ 1 bilhão.',
        );
      }
    }
    final rentText = _rentPriceController.text.trim();
    if (rentText.isNotEmpty) {
      final p = Masks.unmaskMoney(rentText) / 100.0;
      if (p <= 0) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Preço de aluguel deve ser positivo.',
        );
      }
      if (p >= 1000000) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Preço de aluguel deve ser menor que R\$ 999.999,99.',
        );
      }
    }
    final feeText = _condominiumFeeController.text.trim();
    if (feeText.isNotEmpty) {
      final p = Masks.unmaskMoney(feeText) / 100.0;
      if (p <= 0) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Valor do condomínio deve ser positivo.',
        );
      }
      if (p >= 100000) {
        return const _StepValidationFailure(
          step: 3,
          message: 'Valor do condomínio deve ser menor que R\$ 99.999,99.',
        );
      }
    }
    final iptuText = _iptuController.text.trim();
    if (iptuText.isNotEmpty) {
      final p = Masks.unmaskMoney(iptuText) / 100.0;
      if (p <= 0) {
        return const _StepValidationFailure(
          step: 3,
          message: 'IPTU deve ser positivo.',
        );
      }
      if (p >= 100000) {
        return const _StepValidationFailure(
          step: 3,
          message: 'IPTU deve ser menor que R\$ 99.999,99.',
        );
      }
    }
    if (_acceptsNegotiation) {
      if (saleText.isNotEmpty) {
        final minS = _minSalePriceController.text.trim();
        if (minS.isEmpty) {
          return const _StepValidationFailure(
            step: 3,
            message: 'Informe o valor mínimo de venda (negociação ativada).',
          );
        }
        final minPrice = Masks.unmaskMoney(minS) / 100.0;
        if (minPrice <= 0) {
          return const _StepValidationFailure(
            step: 3,
            message: 'Preço mínimo de venda deve ser positivo.',
          );
        }
        final salePrice = Masks.unmaskMoney(saleText) / 100.0;
        if (minPrice >= salePrice) {
          return const _StepValidationFailure(
            step: 3,
            message:
                'O preço mínimo de venda deve ser menor que o preço anunciado.',
          );
        }
      }
      if (rentText.isNotEmpty) {
        final minR = _minRentPriceController.text.trim();
        if (minR.isEmpty) {
          return const _StepValidationFailure(
            step: 3,
            message:
                'Informe o valor mínimo de aluguel (negociação ativada).',
          );
        }
        final minPrice = Masks.unmaskMoney(minR) / 100.0;
        if (minPrice <= 0) {
          return const _StepValidationFailure(
            step: 3,
            message: 'Preço mínimo de aluguel deve ser positivo.',
          );
        }
        final rentPrice = Masks.unmaskMoney(rentText) / 100.0;
        if (minPrice >= rentPrice) {
          return const _StepValidationFailure(
            step: 3,
            message:
                'O preço mínimo de aluguel deve ser menor que o valor anunciado.',
          );
        }
      }
    }

    // ============================ Step 4 — Galeria ============================
    if (!saveAsDraft) {
      final imgCount = _totalSelectableImageCount();
      if (imgCount < _kMinGalleryImagesWeb) {
        return _StepValidationFailure(
          step: 4,
          message:
              'Adicione pelo menos $_kMinGalleryImagesWeb imagens (mesmo mínimo do CRM web).',
        );
      }
      if (imgCount > _kMaxGalleryImagesWeb) {
        return _StepValidationFailure(
          step: 4,
          message:
              'Galeria limitada a $_kMaxGalleryImagesWeb imagens (atual: $imgCount).',
        );
      }
    }

    // ============================ Step 5 — Proprietário ============================
    final ownerName = _ownerNameController.text.trim();
    if (ownerName.isEmpty) {
      return const _StepValidationFailure(
        step: 5,
        message: 'Informe o nome do proprietário.',
      );
    }
    final ownerPhoneDigits =
        _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '');
    if (ownerPhoneDigits.isEmpty) {
      return const _StepValidationFailure(
        step: 5,
        message: 'Informe o telefone do proprietário.',
      );
    }
    final ownerEmail = _ownerEmailController.text.trim();
    if (ownerEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(ownerEmail)) {
      return const _StepValidationFailure(
        step: 5,
        message: 'E-mail do proprietário inválido.',
      );
    }
    if (_formRequiredKeys.contains('internalNotes') &&
        _internalNotesController.text.trim().isEmpty) {
      return const _StepValidationFailure(
        step: 5,
        message:
            'Observações internas obrigatórias (configuração da empresa).',
      );
    }

    return null;
  }

  /// Anima até o step com erro (se necessário) e mostra um SnackBar
  /// vermelho com o motivo. No próximo frame, dispara
  /// `_formKey.currentState.validate()` para que os campos correspondentes
  /// fiquem em vermelho e visíveis para o usuário.
  void _navigateToStepWithError(_StepValidationFailure err) {
    final target = err.step.clamp(0, _totalSteps - 1);
    if (target != _currentStep) {
      try {
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
        );
      } catch (_) {
        try {
          _pageController.jumpToPage(target);
        } catch (_) {/* ignore */}
      }
      _setStateAndPersist(() => _currentStep = target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _formKey.currentState?.validate();
      } catch (_) {/* ignore */}
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.status.error,
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Etapa ${target + 1} · ${_wizardTitles[target]}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      err.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _saveProperty({bool saveAsDraft = false}) async {
    final firstError =
        _findFirstStepValidationError(saveAsDraft: saveAsDraft);
    if (firstError != null) {
      _navigateToStepWithError(firstError);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) {
      // Defesa: se o Form ainda achar algo inválido (ex.: validador
      // específico que não conseguimos espelhar acima), permanece no step
      // atual e dispara o snackbar de revisão.
      _navigateToStepWithError(_StepValidationFailure(
        step: _currentStep,
        message: 'Há campos inválidos nesta etapa. Revise antes de continuar.',
      ));
      return;
    }

    await _ensurePreSubmitConfigLoaded();
    if (!mounted) return;

    final isEditing = widget.propertyId != null;

    if (!saveAsDraft &&
        !isEditing &&
        (!_approvalSettingsFetchOk || !_formSettingsFetchOk)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Não foi possível carregar as regras de aprovação e o formulário '
              'da empresa. Verifique a ligação e tente novamente.',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
      return;
    }

    final resolvedStatus = _resolvedApiStatus(saveAsDraft);
    final pubErr = _checkPublicationRules(
      saveAsDraft: saveAsDraft,
      resolvedStatus: resolvedStatus,
    );
    if (pubErr != null) {
      _navigateToStepWithError(pubErr);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    var navigatingAwayAfterSave = false;

    try {
      String? userId = _currentUserId;
      if (!isEditing && (userId == null || userId.isEmpty)) {
        final prof = await ProfileService.instance.getProfile();
        if (!mounted) return;
        if (prof.success &&
            prof.data != null &&
            prof.data!.id.isNotEmpty) {
          userId = prof.data!.id;
          setState(() => _currentUserId = userId);
        }
      }

      if (!isEditing && (userId == null || userId.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Não foi possível identificar o usuário logado. Tente atualizar ou fazer login novamente.',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
        return;
      }

      final street = _streetController.text.trim();
      final number = _numberController.text.trim();
      final comp = _complementController.text.trim();
      final fullAddress = [
        street,
        number,
        if (comp.isNotEmpty) comp,
      ].join(', ');

      final totalAreaParsed =
          _parseBrazilianAreaToNumber(_totalAreaController.text);

      final builtParsed =
          _parseBrazilianAreaToNumber(_builtAreaController.text);

      final beds = int.tryParse(_bedroomsController.text.trim());
      final baths = int.tryParse(_bathroomsController.text.trim());
      final park = int.tryParse(_parkingSpacesController.text.trim());

      final ownerPhoneDigits =
          _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '');
      final ownerDocDigits =
          _ownerDocumentController.text.replaceAll(RegExp(r'\D'), '').trim();
      final ownerDocApi = ownerDocDigits.isEmpty
          ? null
          : (ownerDocDigits.length > 18
              ? ownerDocDigits.substring(0, 18)
              : ownerDocDigits);

      final suitesParsed = int.tryParse(_suitesController.text.trim());
      final sectorTrim = _sectorController.text.trim();
      final internalTrim = _internalNotesController.text.trim();

      final omitStatusPatch = isEditing &&
          _preservePublicationOnEdit &&
          _loadedPropertyStatus != null &&
          resolvedStatus == _loadedPropertyStatus;

      final omitPubPatch = isEditing &&
          _preservePublicationOnEdit &&
          _loadedPropertyIsAvailableForSite != null &&
          _publishToSite == _loadedPropertyIsAvailableForSite!;

      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'internalNotes': internalTrim.isEmpty ? null : internalTrim,
        'type': _selectedType.value,
        'address': fullAddress,
        'street': street,
        'number': number,
        if (comp.isNotEmpty) 'complement': comp,
        'neighborhood': _neighborhoodController.text.trim(),
        'sector': sectorTrim.isEmpty ? null : sectorTrim,
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'zipCode': _zipCodeController.text.trim(),
        if (totalAreaParsed != null && totalAreaParsed >= 0.01)
          'totalArea': totalAreaParsed,
        'builtArea': builtParsed ?? 0,
        'bedrooms': beds ?? 0,
        'suites': suitesParsed ?? 0,
        'bathrooms': baths ?? 0,
        'parkingSpaces': park ?? 0,
        'salePrice': _salePriceController.text.trim().isNotEmpty
            ? Masks.unmaskMoney(_salePriceController.text) / 100.0
            : 0.0,
        'rentPrice': _rentPriceController.text.trim().isNotEmpty
            ? Masks.unmaskMoney(_rentPriceController.text) / 100.0
            : 0.0,
        'condominiumFee': _condominiumFeeController.text.trim().isNotEmpty
            ? Masks.unmaskMoney(_condominiumFeeController.text) / 100.0
            : 0.0,
        'iptu': _iptuController.text.trim().isNotEmpty
            ? Masks.unmaskMoney(_iptuController.text) / 100.0
            : 0.0,
        'features': _selectedFeatures,
        'acceptsNegotiation': _acceptsNegotiation,
        if (_minSalePriceController.text.trim().isNotEmpty)
          'minSalePrice':
              Masks.unmaskMoney(_minSalePriceController.text) / 100.0,
        if (_minRentPriceController.text.trim().isNotEmpty)
          'minRentPrice':
              Masks.unmaskMoney(_minRentPriceController.text) / 100.0,
        if (_offerBelowMinSaleAction != null &&
            ['reject', 'pending', 'notify']
                .contains(_offerBelowMinSaleAction))
          'offerBelowMinSaleAction': _offerBelowMinSaleAction,
        if (_offerBelowMinRentAction != null &&
            ['reject', 'pending', 'notify']
                .contains(_offerBelowMinRentAction))
          'offerBelowMinRentAction': _offerBelowMinRentAction,
        'ownerName': _ownerNameController.text.trim(),
        'ownerEmail': _ownerEmailController.text.trim(),
        'ownerPhone': ownerPhoneDigits.isNotEmpty
            ? ownerPhoneDigits
            : _ownerPhoneController.text.trim(),
        ...(ownerDocApi != null ? {'ownerDocument': ownerDocApi} : {}),
        if (_ownerAddressController.text.trim().isNotEmpty)
          'ownerAddress': _ownerAddressController.text.trim(),
        // Campos extras alinhados a `buildCreatePropertyApiPayload.ts`
        'isFeatured': _isFeatured,
        'isHighStandard': false,
        'hasPlaque': false,
        'hasExclusivity': false,
        'isPrivate': false,
        'bail': false,
        'suretyBond': false,
        'bondApplication': false,
        'credpagoGuarantee': false,
        'guarantor': false,
      };

      if (!omitStatusPatch) {
        data['status'] = resolvedStatus;
      }
      if (!omitPubPatch) {
        data['isAvailableForSite'] = _publishToSite;
      }

      if (!isEditing) {
        final uid = userId!;
        data['capturedById'] = uid;
        data['capturedByIds'] = [uid];
        data['responsibleUserIds'] = [uid];
      } else {
        final cap = _loadedCapturedById;
        if (cap != null && cap.isNotEmpty) {
          data['capturedById'] = cap;
          data['capturedByIds'] = [cap];
        }
      }

      final tid = _selectedTeamId?.trim();
      if (tid != null && tid.isNotEmpty) {
        data['teamId'] = tid;
      }

      final cid = _selectedCondominiumId?.trim();
      if (cid != null && cid.isNotEmpty) {
        data['condominiumId'] = cid;
      }

      final eid = _selectedEmpreendimentoId?.trim();
      if (eid != null && eid.isNotEmpty) {
        data['empreendimentoId'] = eid;
      }

      // Mesma regra do web (`CreatePropertyPage.tsx` linhas 2522-2523):
      // `condominiumId` / `empreendimentoId` no `_formRequiredKeys` só
      // contam quando o usuário optou pelo modo correspondente. Para
      // `standalone` esses keys são removidos da checagem.
      final effectiveRequired = _formRequiredKeys.where((k) {
        if (k == 'condominiumId') {
          return _addressMode == PropertyCreationAddressMode.condominium;
        }
        if (k == 'empreendimentoId') {
          return _addressMode == PropertyCreationAddressMode.empreendimento;
        }
        return true;
      }).toList();
      final cfgErr = configurableFieldsErrorPt(effectiveRequired, data);
      if (cfgErr != null) {
        // Identificar o primeiro key obrigatório que está vazio para
        // saltar até o step correspondente — paridade com a navegação
        // automática nos validadores acima.
        int? targetStep;
        for (final key in effectiveRequired) {
          if (!isConfigurableFieldPresent(key, data)) {
            targetStep = _fieldStepMap[key];
            if (targetStep != null) break;
          }
        }
        if (mounted) {
          if (_isLoading) setState(() => _isLoading = false);
          _navigateToStepWithError(_StepValidationFailure(
            step: targetStep ?? _currentStep,
            message: cfgErr,
          ));
        }
        return;
      }

      final response = isEditing
          ? await _propertyService.updateProperty(widget.propertyId!, data)
          : await _propertyService.createProperty(data);

      if (mounted) {
        if (response.success && response.data != null) {
          if (_selectedImages.isNotEmpty) {
            await _uploadImages(response.data!.id);
            if (!mounted) return;
          }
          if (!mounted) return;

          if (!saveAsDraft && !isEditing && _activeLocalDraftId != null) {
            try {
              await _draftStorage.delete(_activeLocalDraftId!);
            } catch (_) {}
          }
          // Imóvel criado/atualizado com sucesso — limpa o auto-save anônimo
          // (paridade `localStorage.removeItem(DRAFT_STORAGE_KEY)` web).
          if (!isEditing && !saveAsDraft) {
            await _clearAnonymousDraft();
          }

          if (!mounted) return;

          navigatingAwayAfterSave = true;

          final needsApprovalQueue =
              _requireApprovalToBeAvailable ||
                  _requireOwnerAuthorizationToBeAvailable ||
                  _requireApprovalToPublishOnSite;
          final queuedForApprovals =
              !isEditing && !saveAsDraft && needsApprovalQueue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saveAsDraft
                    ? 'Rascunho salvo!'
                    : (widget.propertyId != null
                          ? 'Propriedade atualizada com sucesso!'
                          : (queuedForApprovals
                              ? 'Imóvel enviado para a fila de aprovação.'
                              : 'Propriedade criada com sucesso!')),
              ),
              backgroundColor: AppColors.status.success,
            ),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final id = response.data!.id;
            Navigator.of(context).pop(
              PropertyWizardPopResult(
                propertyId: id,
                savedDraft: saveAsDraft,
                showApprovalShortcut: queuedForApprovals,
              ),
            );
          });
        } else {
          final raw = (response.message ?? '').trim();
          final lower = raw.toLowerCase();
          // O backend pode rejeitar com "Campo obrigatório conforme
          // configuração da empresa: <Campo>" quando há config legada de
          // `propertyFormRequiredFields`. Mostramos a mensagem do servidor
          // sem alterar (paridade com o web) e oferecemos um atalho rápido
          // para reabrir o setup, sem deslogar nem assumir o motivo.
          final looksLikeCompanyFieldCfg =
              lower.contains('campo obrigatório conforme configuração') ||
                  lower.contains('campo obrigatorio conforme configuracao');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.status.error,
              content: Text(
                raw.isEmpty ? 'Erro ao salvar propriedade' : raw,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              action: looksLikeCompanyFieldCfg && widget.propertyId == null
                  ? SnackBarAction(
                      label: 'Ajustar',
                      textColor: Colors.white,
                      onPressed: () =>
                          _openPropertyCreationSetup(isInitial: false),
                    )
                  : null,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar propriedade: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao conectar com o servidor'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted && !navigatingAwayAfterSave) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String get _wizardScaffoldTitle {
    if (widget.propertyId != null) return 'Editar Imóvel';
    final fromLocalDraft =
        (widget.localDraftId != null && widget.localDraftId!.isNotEmpty) ||
            _activeLocalDraftId != null;
    return fromLocalDraft ? 'Novo imóvel · rascunho local' : 'Novo Imóvel';
  }

  List<Widget>? get _wizardToolbarActions {
    if (widget.propertyId != null) return null;
    return [
      IconButton(
        tooltip: 'Ajustar tipo, equipe e origem do endereço',
        onPressed: _isLoading
            ? null
            : () => _openPropertyCreationSetup(isInitial: false),
        icon: const Icon(Icons.tune_rounded),
      ),
      IconButton(
        tooltip: 'Lista de rascunhos neste dispositivo',
        onPressed: () =>
            Navigator.of(context).pushNamed(AppRoutes.propertyDraftsLocal),
        icon: const Icon(Icons.folder_special_rounded),
      ),
      IconButton(
        tooltip: 'Guardar rascunho local (com nome)',
        onPressed: _isLoading ? null : _showSaveLocalDraftSheet,
        icon: const Icon(Icons.bookmark_add_rounded),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingProperty) {
      return AppScaffold(
        title: _wizardScaffoldTitle,
        actions: _wizardToolbarActions,
        body: DecoratedBox(
          decoration: _wizardBackdropDecoration(context),
          child: _buildSkeleton(context, theme),
        ),
      );
    }

    return AppScaffold(
      title: _wizardScaffoldTitle,
      actions: _wizardToolbarActions,
      body: DecoratedBox(
        decoration: _wizardBackdropDecoration(context),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_anonymousDraftRestored) _buildAnonymousDraftRestoredBanner(theme),
              _buildStepIndicator(theme),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1BasicInfo(theme),
                    _buildStep2Location(theme),
                    _buildStep3Characteristics(theme),
                    _buildStep4Values(theme),
                    _buildStep5Gallery(theme),
                    _buildStep6Clients(theme),
                    _buildStep7Review(theme),
                  ],
                ),
              ),
              _buildNavigationButtons(theme),
            ],
          ),
        ),
      ),
    );
  }

  bool _wizIsDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Fundo do wizard — minimalista, alinhado às demais telas (Dashboard, Imóveis, CRM).
  /// Em dark: cor base sólida do app (sem gradientes coloridos).
  /// Em light: gradiente muito sutil entre os tons neutros do app.
  BoxDecoration _wizardBackdropDecoration(BuildContext context) {
    final isDark = _wizIsDark(context);
    if (isDark) {
      return BoxDecoration(
        color: AppColors.background.backgroundDarkMode,
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 1.0],
        colors: [
          AppColors.background.background,
          AppColors.background.backgroundSecondary,
        ],
      ),
    );
  }

  Color _wizBrand(BuildContext context) => _wizIsDark(context)
      ? AppColors.primary.primaryLightDarkMode
      : AppColors.primary.primary;

  Color _wizBrandMuted(BuildContext context) => _wizIsDark(context)
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primaryDark;

  /// Tom frio para chips, badges e progresso — equilibra a marca vermelha.
  Color _wizCool(BuildContext context) => _wizIsDark(context)
      ? AppColors.status.infoDarkMode
      : AppColors.status.info;

  /// Tema fluido para os campos do wizard — alinha-se ao resto do app (CRM,
  /// Imóveis, Dashboard): fill quase imperceptível por cima do card da seção,
  /// borda fina, foco no acento da etapa, raio 12.
  ///
  /// Aplicado por `Theme(data: ...)` ao redor do conteúdo de cada seção,
  /// portanto vale para `CustomTextField`, `DropdownButtonFormField`,
  /// `_buildFormField` e qualquer `TextFormField` interno — sem que cada
  /// componente precise re-declarar o estilo.
  ThemeData _wizardFieldTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final accent = _stepAccent(_currentStep);

    final softBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);
    final hoverBorder = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.85);

    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.white.withValues(alpha: 0.78),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: base.textTheme.labelLarge?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        floatingLabelStyle: base.textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context)
              .withValues(alpha: isDark ? 0.55 : 0.62),
          fontWeight: FontWeight.w500,
        ),
        helperStyle: base.textTheme.labelSmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        prefixIconColor: ThemeHelpers.textSecondaryColor(context),
        suffixIconColor: ThemeHelpers.textSecondaryColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: softBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: softBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: softBorder.withValues(alpha: 0.5),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.status.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.status.error,
            width: 1.4,
          ),
        ),
        hoverColor: hoverBorder.withValues(alpha: 0.05),
      ),
      switchTheme: SwitchThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        trackOutlineWidth: WidgetStateProperty.resolveWith((_) => 1),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.0);
          }
          return softBorder;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark
              ? Colors.white.withValues(alpha: 0.78)
              : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return isDark
              ? Colors.white.withValues(alpha: 0.06)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.20);
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(
                color: accent.withValues(alpha: 0.55),
                width: 1.2,
              );
            }
            return BorderSide(color: softBorder);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent.withValues(alpha: isDark ? 0.18 : 0.10);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return ThemeHelpers.textColor(context);
          }),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              fontSize: 13,
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          iconSize: const WidgetStatePropertyAll(16),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return ThemeHelpers.textSecondaryColor(context);
          }),
          overlayColor:
              WidgetStateProperty.all(accent.withValues(alpha: 0.06)),
        ),
        selectedIcon: const Icon(Icons.check_rounded, size: 14),
      ),
      chipTheme: _wizardChipTheme(base),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: base.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark
                ? AppColors.background.backgroundDarkMode
                : AppColors.background.background,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: softBorder),
            ),
          ),
          elevation: const WidgetStatePropertyAll(8),
        ),
      ),
    );
  }

  /// Stepper "constelação" — 7 nós conectados por trilha + faixa em gradiente
  /// proporcional ao progresso. Sem scroll horizontal e sem listas Row clássicas:
  /// cada nó ocupa apenas o espaço do círculo; o trilho conector ocupa o resto.
  Widget _buildStepIndicator(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final cur = _currentStep.clamp(0, _totalSteps - 1);
    final accent = _stepAccent(cur);

    final trackBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.32);
    final progressGrad = LinearGradient(
      colors: [
        Color.lerp(accent, _wizCool(context), 0.35)!.withValues(alpha: 0.85),
        accent,
      ],
    );

    final nodes = <Widget>[];
    for (var i = 0; i < _totalSteps; i++) {
      final done = i < cur;
      final isCur = i == cur;
      final base = _stepAccent(i);
      final size = isCur ? 30.0 : 22.0;

      final ring = isCur
          ? Container(
              width: size + 10,
              height: size + 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: base.withValues(alpha: 0.16),
                border: Border.all(
                  color: base.withValues(alpha: 0.42),
                ),
              ),
              alignment: Alignment.center,
            )
          : null;

      final dot = AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCur
              ? base
              : done
                  ? base.withValues(alpha: 0.85)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white),
          border: Border.all(
            color: isCur || done
                ? base
                : (isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.55)),
            width: isCur ? 0 : 1,
          ),
          boxShadow: isCur
              ? [
                  BoxShadow(
                    color: base.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: isCur ? 13 : 11,
                  fontWeight: FontWeight.w900,
                  color: isCur
                      ? Colors.white
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : ThemeHelpers.textSecondaryColor(context)),
                ),
              ),
      );

      nodes.add(
        SizedBox(
          width: 36,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ?ring,
              dot,
            ],
          ),
        ),
      );

      if (i < _totalSteps - 1) {
        nodes.add(
          Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: i < cur ? null : trackBg,
                gradient: i < cur ? progressGrad : null,
              ),
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: nodes,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Etapa ${cur + 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                ' · ',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              Expanded(
                child: Text(
                  _wizardTitles[cur],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              Text(
                '${cur + 1}/$_totalSteps',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textSecondaryColor(context),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Hero da etapa — ícone tonal + chip de etapa + título + subtítulo.
  /// Usa a identidade visual da marca (vermelho) com acento da etapa atual,
  /// sem cards aninhados nem listas; é uma única assinatura visual no topo.
  Widget _wizardStepHeader(ThemeData theme) {
    final step = _currentStep.clamp(0, _totalSteps - 1);
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(step);
    final brand = _wizBrand(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(accent, brand, isDark ? 0.18 : 0.08)!,
                Color.lerp(accent, brand, isDark ? 0.42 : 0.28)!
                    .withValues(alpha: 0.92),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            _stepIcon(step),
            color: Colors.white.withValues(alpha: 0.96),
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  'ETAPA ${step + 1} · $_totalSteps',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _wizardTitles[step],
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _wizardSubtitles[step],
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.42,
                  fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) + 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Seção fluida do wizard — sem card/borda. Só "eyebrow" com ícone tonal +
  /// título, linha hairline tonal e o conteúdo edge-to-edge usando toda a
  /// largura do scroll. Desenho próximo de uma "página de revista":
  /// inspiração em Imóveis e Kanban, onde o conteúdo respira sem caixas.
  Widget _wizardSection(
    ThemeData theme, {
    required String title,
    String? subtitle,
    Widget? trailing,
    IconData? icon,
    required Widget child,
  }) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.40);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: accent,
                      fontSize: 11,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: hairline),
        const SizedBox(height: 14),
        Theme(
          data: _wizardFieldTheme(context),
          child: child,
        ),
      ],
    );
  }

  Widget _wizardHintBanner(
    ThemeData theme, {
    required String message,
    Color? accent,
    IconData icon = Icons.tips_and_updates_outlined,
  }) {
    final isDark = _wizIsDark(context);
    final base =
        accent ?? (isDark ? _wizCool(context) : _wizBrandMuted(context));

    final fill = Color.lerp(
          base.withValues(alpha: isDark ? 0.22 : 0.12),
          Colors.white.withValues(alpha: isDark ? 0.04 : 0.5),
          0.5,
        ) ??
        base.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            fill,
            base.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.32 : 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: base.withValues(alpha: 0.95)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner sutil mostrado quando o auto-save anônimo restaurou o que o
  /// usuário tinha preenchido antes (paridade `localStorage` web). Permite
  /// descartar o rascunho com confirmação para começar do zero.
  Widget _buildAnonymousDraftRestoredBanner(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final accent = _wizCool(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.40 : 0.30),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rascunho deste dispositivo restaurado — continue de onde parou.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : _confirmDiscardAnonymousDraft,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Descartar',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner informativo quando o endereço vem de um condomínio ou
  /// empreendimento vinculado (paridade com o web — ali os campos ficam
  /// editáveis mas o endereço é pré-preenchido). Mostra o nome da entidade
  /// vinculada e um atalho "Trocar configuração" que reabre o setup.
  Widget _buildLinkedAddressBanner(
    ThemeData theme, {
    required bool isCondo,
    required String? entityName,
    required bool loading,
  }) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.78);
    final border = accent.withValues(alpha: isDark ? 0.30 : 0.22);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: fill,
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
            ),
            child: Icon(
              isCondo ? Icons.apartment_rounded : Icons.location_city_rounded,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCondo
                      ? 'VINCULADO A CONDOMÍNIO'
                      : 'VINCULADO A EMPREENDIMENTO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    fontSize: 10,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading
                      ? 'Carregando endereço do cadastro…'
                      : (entityName ?? '—'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'CEP e endereço vêm do cadastro. Você pode revisar abaixo se '
                  'precisar ajustar algo na unidade.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _openPropertyCreationSetup(isInitial: false),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Trocar',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Faixa "tipo · origem do endereço" que substitui o ChoiceChip de tipo
  /// quando estamos em criação fresca (web `CreatePropertyPage` → linha 4070).
  /// O tipo já vem fixado pelo modal de pré-criação; aqui só há um botão
  /// "Alterar" que reabre o setup.
  Widget _buildTypeSummaryRow(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);
    final modeLabel = _addressMode == PropertyCreationAddressMode.condominium
        ? '· Endereço pelo condomínio'
        : _addressMode == PropertyCreationAddressMode.empreendimento
            ? '· Endereço pelo empreendimento'
            : '· Endereço próprio (CEP)';

    IconData typeIcon(PropertyType t) {
      switch (t) {
        case PropertyType.house:
          return Icons.home_rounded;
        case PropertyType.apartment:
          return Icons.apartment_rounded;
        case PropertyType.commercial:
          return Icons.business_rounded;
        case PropertyType.land:
          return Icons.location_on_rounded;
        case PropertyType.rural:
          return Icons.cottage_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.78),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.30 : 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
            ),
            child: Icon(typeIcon(_selectedType), size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedType.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  modeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _isLoading
                ? null
                : () => _openPropertyCreationSetup(isInitial: false),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Alterar'),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tema dos chips dentro do wizard — pill totalmente arredondada, borda
  /// hairline; quando selecionado, fill suave no acento da etapa e texto na
  /// cor do acento (peso 800). Sem checkmark por padrão (override por chip
  /// quando precisar). Usado por `ChoiceChip` e `FilterChip`.
  ChipThemeData _wizardChipTheme(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    return ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: accent.withValues(alpha: 0.55), width: 1.2);
        }
        return BorderSide(color: border);
      }),
      showCheckmark: false,
      checkmarkColor: accent,
      selectedColor: accent.withValues(alpha: isDark ? 0.18 : 0.10),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.035)
          : Colors.white.withValues(alpha: 0.70),
      labelStyle: theme.textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        fontSize: 13,
      ),
      secondaryLabelStyle: theme.textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.1,
        fontSize: 13,
        color: accent,
      ),
      brightness: theme.brightness,
    );
  }

  /// Decoração refinada para `DropdownButtonFormField` dentro do wizard.
  /// Usa o `_wizardFieldTheme` (fill, borda, foco) e adiciona um ícone
  /// leading discreto na cor de acento da etapa.
  InputDecoration _wizardDropdownDecoration(
    String labelText, {
    IconData? icon,
    String? hint,
  }) {
    final accent = _stepAccent(_currentStep);
    return InputDecoration(
      labelText: labelText,
      hintText: hint,
      prefixIcon: icon != null
          ? Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Icon(icon, size: 18, color: accent),
            )
          : null,
      prefixIconConstraints: icon != null
          ? const BoxConstraints(minWidth: 36, minHeight: 36)
          : null,
    );
  }

  /// Linha de toggle (switch) refinada e fluida — sem caixa/borda. Apenas
  /// um ícone tonal, título, subtítulo e o switch alinhado à direita.
  /// Usa o `switchTheme` herdado de `_wizardFieldTheme` (acento da etapa).
  Widget _wizardSwitchRow(
    ThemeData theme, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
  }) {
    final accent = _stepAccent(_currentStep);
    final isDark = _wizIsDark(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.32,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Transform.scale(
              scale: 0.88,
              alignment: Alignment.centerRight,
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1BasicInfo(ThemeData theme) {
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.auto_awesome_rounded,
            title: 'Gerar texto com IA',
            subtitle:
                'Na última etapa você pode criar ou ajustar título e descrição automaticamente.',
            child: _wizardSwitchRow(
              theme,
              icon: Icons.auto_awesome_rounded,
              title: 'Preencher título e descrição na revisão',
              subtitle: _autoGenerateOnReview
                  ? 'Ao final, a IA usa os dados do formulário para sugerir título e descrição.'
                  : 'Informe manualmente aqui ou use o botão de IA na etapa final.',
              value: _autoGenerateOnReview,
              onChanged: (value) =>
                  _setStateAndPersist(() => _autoGenerateOnReview = value),
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.title_rounded,
            title: 'Texto do anúncio',
            subtitle: _autoGenerateOnReview
                ? 'Opcional agora — preencha se quiser adiantar revisão.'
                : 'Informe título e descrição antes de prosseguir.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _titleController,
                  label: _autoGenerateOnReview ? 'Título' : 'Título *',
                  hint: 'Ex: Casa com 3 quartos em condomínio fechado',
                  maxLength: 255,
                  validator: (value) {
                    if (!_autoGenerateOnReview) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Título é obrigatório ou ative a geração automática com IA';
                      }
                      if (value.trim().length < 3) {
                        return 'Título deve ter pelo menos 3 caracteres';
                      }
                      if (value.trim().length > 255) {
                        return 'Título deve ter no máximo 255 caracteres';
                      }
                    } else {
                      if (value != null && value.trim().isNotEmpty) {
                        if (value.trim().length < 3) {
                          return 'Título deve ter pelo menos 3 caracteres';
                        }
                        if (value.trim().length > 255) {
                          return 'Título deve ter no máximo 255 caracteres';
                        }
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _descriptionController,
                  label: _autoGenerateOnReview ? 'Descrição' : 'Descrição *',
                  hint: 'Descreva o imóvel em detalhes...',
                  maxLines: 6,
                  maxLength: 5000,
                  validator: (value) {
                    if (!_autoGenerateOnReview) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Descrição é obrigatória ou ative a geração automática com IA';
                      }
                      if (value.trim().length < 10) {
                        return 'Descrição deve ter pelo menos 10 caracteres';
                      }
                      if (value.trim().length > 5000) {
                        return 'Descrição deve ter no máximo 5000 caracteres';
                      }
                    } else {
                      if (value != null && value.trim().isNotEmpty) {
                        if (value.trim().length < 10) {
                          return 'Descrição deve ter pelo menos 10 caracteres';
                        }
                        if (value.trim().length > 5000) {
                          return 'Descrição deve ter no máximo 5000 caracteres';
                        }
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.category_rounded,
            title: 'Tipo de imóvel *',
            subtitle: widget.propertyId == null
                ? 'Definido no início — toque em "Alterar" para revisar com o endereço.'
                : 'Escolha a categoria que melhor representa o anúncio.',
            child: widget.propertyId == null
                ? _buildTypeSummaryRow(theme)
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PropertyType.values.map((type) {
                      final isSelected = _selectedType == type;
                      return ChoiceChip(
                        label: Text(type.label),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            _setStateAndPersist(() => _selectedType = type);
                          }
                        },
                      );
                    }).toList(),
                  ),
          ),
          if (_formRequiredKeys.contains('teamId') || _formTeams.isNotEmpty) ...[
            SizedBox(height: _wizGapBetweenSections),
            _wizardSection(
              theme,
              icon: Icons.groups_2_rounded,
              title: _formRequiredKeys.contains('teamId')
                  ? 'Equipe *'
                  : 'Equipe',
              subtitle:
                  'Opções vindas do CRM (`/properties/form-settings`), mesma regra do cadastro web.',
              child: _formRequiredKeys.contains('teamId') && _formTeams.isEmpty
                  ? Text(
                      'Nenhuma equipe disponível para sua conta. Ajuste as '
                      'configurações de cadastro no CRM.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.status.error,
                      ),
                    )
                  : DropdownButtonFormField<String?>(
                      initialValue: _selectedTeamId,
                      decoration: _wizardDropdownDecoration(
                        'Selecionar equipe',
                        icon: Icons.groups_2_rounded,
                      ),
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      isExpanded: true,
                      items: [
                        if (!_formRequiredKeys.contains('teamId'))
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— Não vincular —'),
                          ),
                        ..._formTeams.map(
                          (t) => DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _formTeams.isEmpty
                          ? null
                          : (v) => _setStateAndPersist(() => _selectedTeamId = v),
                      validator: _formRequiredKeys.contains('teamId')
                          ? (v) => (v == null || v.isEmpty)
                              ? 'Selecione uma equipe'
                              : null
                          : null,
                    ),
            ),
          ],
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.lock_outline_rounded,
            title: _formRequiredKeys.contains('internalNotes')
                ? 'Observações internas *'
                : 'Observações internas',
            subtitle:
                'Uso da equipe; não são publicadas no site (como no CRM web).',
            child: CustomTextField(
              controller: _internalNotesController,
              label: 'Observações internas',
              hint: 'Notas internas para a equipe…',
              maxLines: 4,
              maxLength: 10000,
              validator: (value) {
                if (_formRequiredKeys.contains('internalNotes')) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Campo obrigatório (configuração da empresa)';
                  }
                }
                if (value != null && value.trim().length > 10000) {
                  return 'Máximo 10.000 caracteres';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Location(ThemeData theme) {
    final linkedToCondo =
        _addressMode == PropertyCreationAddressMode.condominium;
    final linkedToEmp =
        _addressMode == PropertyCreationAddressMode.empreendimento;
    final linked = linkedToCondo || linkedToEmp;

    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          if (linked) ...[
            _buildLinkedAddressBanner(
              theme,
              isCondo: linkedToCondo,
              entityName: _addressLinkedEntityName,
              loading: _isPrefillingFromLinkedEntity,
            ),
            SizedBox(height: _wizGapBetweenSections),
          ],
          _wizardSection(
            theme,
            icon: Icons.travel_explore_rounded,
            title: 'Busca por CEP',
            subtitle:
                'Toque na lupa para consultar quando o número estiver completo.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _zipCodeController,
                  label: 'CEP *',
                  hint: '00000-000',
                  keyboardType: TextInputType.number,
                  inputFormatters: [CepInputFormatter()],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'CEP é obrigatório';
                    }
                    final cep = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (cep.length != 8) {
                      return 'CEP deve ter 8 dígitos';
                    }
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.search_rounded,
                      color: _wizBrand(context),
                    ),
                    onPressed: _searchCep,
                    tooltip: 'Buscar CEP',
                  ),
                ),
                const SizedBox(height: 12),
                _wizardHintBanner(
                  theme,
                  icon: Icons.map_outlined,
                  message:
                      'Ao informar um CEP válido, tentamos completar ruas, cidade e estado automaticamente.',
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.signpost_rounded,
            title: 'Logradouro',
            subtitle: 'Nome da rua, número e opcionalmente complemento.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CustomTextField(
                        controller: _streetController,
                        label: 'Rua *',
                        hint: 'Nome da rua',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Rua é obrigatória';
                          }
                          if (value.trim().length < 2) {
                            return 'Rua deve ter pelo menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: CustomTextField(
                        controller: _numberController,
                        label: 'Nº *',
                        hint: '123',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Número é obrigatório';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _complementController,
                  label: _formRequiredKeys.contains('complement')
                      ? 'Complemento *'
                      : 'Complemento',
                  hint: 'Apartamento, bloco, sala…',
                  validator: (value) {
                    if (_formRequiredKeys.contains('complement')) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Complemento obrigatório (configuração da empresa)';
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.holiday_village_rounded,
            title: 'Bairro e região',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _neighborhoodController,
                  label: 'Bairro *',
                  hint: 'Nome do bairro',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bairro é obrigatório';
                    }
                    if (value.trim().length < 2) {
                      return 'Bairro deve ter pelo menos 2 caracteres';
                    }
                    if (value.trim().length > 100) {
                      return 'Bairro deve ter no máximo 100 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _sectorController,
                  label: _formRequiredKeys.contains('sector')
                      ? 'Setor *'
                      : 'Setor',
                  hint: 'Região administrativa, zona…',
                  maxLength: 100,
                  validator: (value) {
                    if (_formRequiredKeys.contains('sector')) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Setor obrigatório (configuração da empresa)';
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.location_city_rounded,
            title: 'Cidade e UF',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    controller: _cityController,
                    label: 'Cidade *',
                    hint: 'Nome da cidade',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Cidade é obrigatória';
                      }
                      if (value.trim().length < 2) {
                        return 'Cidade deve ter pelo menos 2 caracteres';
                      }
                      if (value.trim().length > 100) {
                        return 'Cidade deve ter no máximo 100 caracteres';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFormField(
                    theme,
                    controller: _stateController,
                    label: 'UF *',
                    hint: 'SP',
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Estado é obrigatório';
                      }
                      final state = value.trim().toUpperCase();
                      if (state.length != 2) {
                        return 'Digite 2 letras';
                      }
                      if (!RegExp(r'^[A-Z]{2}$').hasMatch(state)) {
                        return 'Apenas letras maiúsculas';
                      }
                      if (state != value) {
                        _stateController.value = TextEditingValue(
                          text: state,
                          selection: TextSelection.collapsed(
                            offset: state.length,
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          // Em criação fresca, o vínculo (condomínio/empreendimento) é
          // definido no modal de pré-criação — esta seção fica reservada
          // para edição, onde o usuário pode revisar/trocar manualmente.
          if (widget.propertyId != null &&
              (_formRequiredKeys.contains('condominiumId') ||
                  _formRequiredKeys.contains('empreendimentoId') ||
                  _condominiumOptions.isNotEmpty ||
                  _empreendimentoOptions.isNotEmpty ||
                  (_selectedCondominiumId != null &&
                      _selectedCondominiumId!.isNotEmpty) ||
                  (_selectedEmpreendimentoId != null &&
                      _selectedEmpreendimentoId!.isNotEmpty))) ...[
            SizedBox(height: _wizGapBetweenSections),
            _wizardSection(
              theme,
              icon: Icons.apartment_rounded,
              title: 'Condomínio e empreendimento',
              subtitle:
                  'Mesma configuração obrigatória opcional do CRM (`propertyFormRequiredFields`).',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_formRequiredKeys.contains('condominiumId') &&
                      _condominiumOptions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Não foi possível listar condomínios (permissão ou rede). '
                        'Tente no CRM ou verifique `condominium:view`.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.status.error,
                        ),
                      ),
                    ),
                  if (_formRequiredKeys.contains('condominiumId') ||
                      _condominiumOptions.isNotEmpty ||
                      (_selectedCondominiumId != null &&
                          _selectedCondominiumId!.isNotEmpty))
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedCondominiumId,
                      decoration: _wizardDropdownDecoration(
                        _formRequiredKeys.contains('condominiumId')
                            ? 'Condomínio *'
                            : 'Condomínio',
                        icon: Icons.apartment_rounded,
                      ),
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      isExpanded: true,
                      items: [
                        if (!_formRequiredKeys.contains('condominiumId'))
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— Nenhum —'),
                          ),
                        ..._condominiumOptions.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              c.name.isNotEmpty ? c.name : c.id,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged:
                          _condominiumOptions.isEmpty && !_formRequiredKeys.contains('condominiumId')
                              ? null
                              : (v) =>
                                  _setStateAndPersist(() {
                                    _selectedCondominiumId = v;
                                    // Em edição, sincroniza o modo de
                                    // endereço com a escolha do dropdown.
                                    _addressMode = (v != null && v.isNotEmpty)
                                        ? PropertyCreationAddressMode.condominium
                                        : (_selectedEmpreendimentoId != null &&
                                                _selectedEmpreendimentoId!.isNotEmpty)
                                            ? PropertyCreationAddressMode.empreendimento
                                            : PropertyCreationAddressMode.standalone;
                                  }),
                      validator: _formRequiredKeys.contains('condominiumId')
                          ? (v) => (v == null || v.isEmpty)
                              ? 'Selecione um condomínio'
                              : null
                          : null,
                    ),
                  if (_formRequiredKeys.contains('empreendimentoId') &&
                      _empreendimentoOptions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 10),
                      child: Text(
                        'Não foi possível listar empreendimentos. Verifique permissões ou CRM.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.status.error,
                        ),
                      ),
                    ),
                  if (_formRequiredKeys.contains('empreendimentoId') ||
                      _empreendimentoOptions.isNotEmpty ||
                      (_selectedEmpreendimentoId != null &&
                          _selectedEmpreendimentoId!.isNotEmpty)) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedEmpreendimentoId,
                      decoration: _wizardDropdownDecoration(
                        _formRequiredKeys.contains('empreendimentoId')
                            ? 'Empreendimento *'
                            : 'Empreendimento',
                        icon: Icons.location_city_rounded,
                      ),
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      isExpanded: true,
                      items: [
                        if (!_formRequiredKeys.contains('empreendimentoId'))
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— Nenhum —'),
                          ),
                        ..._empreendimentoOptions.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              c.name.isNotEmpty ? c.name : c.id,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _empreendimentoOptions.isEmpty &&
                              !_formRequiredKeys.contains('empreendimentoId')
                          ? null
                          : (v) =>
                              _setStateAndPersist(() {
                                _selectedEmpreendimentoId = v;
                                _addressMode = (v != null && v.isNotEmpty)
                                    ? PropertyCreationAddressMode.empreendimento
                                    : (_selectedCondominiumId != null &&
                                            _selectedCondominiumId!.isNotEmpty)
                                        ? PropertyCreationAddressMode.condominium
                                        : PropertyCreationAddressMode.standalone;
                              }),
                      validator:
                          _formRequiredKeys.contains('empreendimentoId')
                              ? (v) => (v == null || v.isEmpty)
                                  ? 'Selecione um empreendimento'
                                  : null
                              : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3Characteristics(ThemeData theme) {
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.straighten_rounded,
            title: 'Metragens',
            subtitle: 'Informe pelo menos a área total livre útil quando souber.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFormField(
                    theme,
                    controller: _totalAreaController,
                    label: 'Área total (m²) *',
                    hint: '0.0',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Área total é obrigatória';
                      }
                      final area = double.tryParse(value);
                      if (area == null || area <= 0) {
                        return 'Área deve ser maior que zero';
                      }
                      if (area >= 1000000) {
                        return 'Área total deve ser menor que 1.000.000 m²';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFormField(
                    theme,
                    controller: _builtAreaController,
                    label: 'Área construída (m²)',
                    hint: '0.0',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final area = double.tryParse(value);
                        if (area != null) {
                          if (area <= 0) {
                            return 'Área construída deve ser positiva';
                          }
                          if (area >= 1000000) {
                            return 'Área construída deve ser menor que 1.000.000 m²';
                          }
                          final totalArea = double.tryParse(
                            _totalAreaController.text,
                          );
                          if (totalArea != null && area > totalArea) {
                            return 'Não pode exceder a área total';
                          }
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.bed_rounded,
            title: 'Cômodos e vagas',
            subtitle: 'Use zero nos campos que não se aplicam.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _bedroomsController,
                        label: 'Quartos',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final bedrooms = int.tryParse(value);
                            if (bedrooms != null && bedrooms < 0) {
                              return 'Valor inválido';
                            }
                            if (bedrooms != null && bedrooms >= 50) {
                              return 'Menor que 50';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _bathroomsController,
                        label: 'Banheiros',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final bathrooms = int.tryParse(value);
                            if (bathrooms != null && bathrooms < 0) {
                              return 'Valor inválido';
                            }
                            if (bathrooms != null && bathrooms >= 20) {
                              return 'Menor que 20';
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _suitesController,
                        label: _formRequiredKeys.contains('suites')
                            ? 'Suítes *'
                            : 'Suítes',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (_formRequiredKeys.contains('suites')) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe suítes (config. da empresa)';
                            }
                          }
                          if (value != null && value.trim().isNotEmpty) {
                            final s = int.tryParse(value);
                            if (s != null && s < 0) return 'Valor inválido';
                            if (s != null && s >= 50) return 'Menor que 50';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _parkingSpacesController,
                        label: 'Vagas',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final parking = int.tryParse(value);
                            if (parking != null && parking < 0) {
                              return 'Valor inválido';
                            }
                            if (parking != null && parking >= 20) {
                              return 'Menor que 20';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.star_rounded,
            title: 'Destaques e comodidades',
            subtitle:
                'Toque para marcar — ajudam filtros internos e a descrição com IA.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                  'Ar condicionado',
                  'Aquecimento',
                  'Elevador',
                  'Portaria 24h',
                  'Segurança 24h',
                  'Piscina',
                  'Academia',
                  'Playground',
                  'Churrasqueira',
                  'Área gourmet',
                  'Jardim',
                  'Terraço',
                  'Varanda',
                  'Sacada',
                  'Vista para o mar',
                  'Vista para a montanha',
                  'Próximo ao metrô',
                  'Próximo a escolas',
                  'Próximo a hospitais',
                  'Próximo a shopping',
                  'Garagem coberta',
                  'Garagem descoberta',
                  'Depósito',
                  'Lavanderia',
                  'Closet',
                  'Home office',
                  'Lareira',
                  'Sistema de alarme',
                  'Câmeras de segurança',
                  'Interfone',
                  'Antena parabólica',
                  'TV a cabo',
                  'Internet',
                  'Gás encanado',
                  'Água quente',
                  'Energia solar',
                  'Mobiliado',
                  'Semi-mobiliado',
                  'Pronto para morar',
                  'Em construção',
                  'Novo',
                  'Usado',
                ]
                    .map((feature) {
                      final isSelected = _selectedFeatures.contains(feature);
                      return FilterChip(
                        label: Text(feature),
                        selected: isSelected,
                        showCheckmark: true,
                        onSelected: (selected) {
                          _setStateAndPersist(() {
                            if (selected) {
                              _selectedFeatures.add(feature);
                            } else {
                              _selectedFeatures.remove(feature);
                            }
                          });
                        },
                      );
                    })
                    .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Values(ThemeData theme) {
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.payments_rounded,
            title: 'Anúncio',
            subtitle: 'Informe apenas o que o imóvel oferece hoje.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _salePriceController,
                        label: 'Venda',
                        hint: 'R\$ 0,00',
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoneyInputFormatter()],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final price = Masks.unmaskMoney(value) / 100.0;
                            if (price <= 0) {
                              return 'Preço de venda deve ser positivo';
                            }
                            if (price >= 1000000000) {
                              return 'Preço de venda deve ser menor que R\$ 1 bilhão';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _rentPriceController,
                        label: 'Aluguel',
                        hint: 'R\$ 0,00',
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoneyInputFormatter()],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final price = Masks.unmaskMoney(value) / 100.0;
                            if (price <= 0) {
                              return 'Preço de aluguel deve ser positivo';
                            }
                            if (price >= 1000000) {
                              return 'Preço de aluguel deve ser menor que R\$ 999.999,99';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _condominiumFeeController,
                        label: 'Condomínio',
                        hint: 'R\$ 0,00',
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoneyInputFormatter()],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final fee = Masks.unmaskMoney(value) / 100.0;
                            if (fee <= 0) {
                              return 'Valor do condomínio deve ser positivo';
                            }
                            if (fee >= 100000) {
                              return 'Valor do condomínio deve ser menor que R\$ 99.999,99';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        theme,
                        controller: _iptuController,
                        label: 'IPTU',
                        hint: 'R\$ 0,00',
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoneyInputFormatter()],
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final iptu = Masks.unmaskMoney(value) / 100.0;
                            if (iptu <= 0) {
                              return 'IPTU deve ser positivo';
                            }
                            if (iptu >= 100000) {
                              return 'IPTU deve ser menor que R\$ 99.999,99';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.handshake_rounded,
            title: 'Negociação',
            subtitle: 'Opcional — ative para registrar mínimos e respostas automáticas.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _wizardSwitchRow(
                  theme,
                  icon: Icons.handshake_rounded,
                  title: 'Aceita negociação',
                  subtitle:
                      'Permite ofertas entre o valor anunciado e o mínimo definido.',
                  value: _acceptsNegotiation,
                  onChanged: (value) =>
                      _setStateAndPersist(() => _acceptsNegotiation = value),
                ),
                if (_acceptsNegotiation) ...[
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFormField(
                          theme,
                          controller: _minSalePriceController,
                          label: 'Mínimo (venda)',
                          hint: 'R\$ 0,00',
                          keyboardType: TextInputType.number,
                          inputFormatters: [MoneyInputFormatter()],
                          validator: (value) {
                            final salePriceText =
                                _salePriceController.text.trim();
                            if (salePriceText.isNotEmpty) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Obrigatório com valor de venda';
                              }
                              final minPrice =
                                  Masks.unmaskMoney(value) / 100.0;
                              if (minPrice <= 0) {
                                return 'Preço mínimo deve ser positivo';
                              }
                              final salePrice =
                                  Masks.unmaskMoney(salePriceText) / 100.0;
                              if (minPrice >= salePrice) {
                                return 'Menor que o preço anunciado';
                              }
                            }
                            if (value != null &&
                                value.trim().isNotEmpty &&
                                Masks.unmaskMoney(value) / 100.0 <= 0) {
                              return 'Preço mínimo deve ser positivo';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFormField(
                          theme,
                          controller: _minRentPriceController,
                          label: 'Mínimo (aluguel)',
                          hint: 'R\$ 0,00',
                          keyboardType: TextInputType.number,
                          inputFormatters: [MoneyInputFormatter()],
                          validator: (value) {
                            final rentPriceText =
                                _rentPriceController.text.trim();
                            if (rentPriceText.isNotEmpty) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Obrigatório com valor de aluguel';
                              }
                              final minPrice =
                                  Masks.unmaskMoney(value) / 100.0;
                              if (minPrice <= 0) {
                                return 'Preço mínimo deve ser positivo';
                              }
                              final rentPrice =
                                  Masks.unmaskMoney(rentPriceText) / 100.0;
                              if (minPrice >= rentPrice) {
                                return 'Menor que o valor anunciado';
                              }
                            }
                            if (value != null &&
                                value.trim().isNotEmpty &&
                                Masks.unmaskMoney(value) / 100.0 <= 0) {
                              return 'Preço mínimo deve ser positivo';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SE RECEBER OFERTA ABAIXO DO MÍNIMO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      fontSize: 10,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _offerBelowMinSaleAction,
                          decoration: _wizardDropdownDecoration(
                            'Canal — venda',
                            icon: Icons.sell_rounded,
                          ),
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          items: const [
                            DropdownMenuItem(
                              value: 'reject',
                              child: Text('Rejeitar'),
                            ),
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('Pendente'),
                            ),
                            DropdownMenuItem(
                              value: 'notify',
                              child: Text('Notificar'),
                            ),
                          ],
                          onChanged: (value) {
                            _setStateAndPersist(() {
                              _offerBelowMinSaleAction = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _offerBelowMinRentAction,
                          decoration: _wizardDropdownDecoration(
                            'Canal — aluguel',
                            icon: Icons.event_repeat_rounded,
                          ),
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          items: const [
                            DropdownMenuItem(
                              value: 'reject',
                              child: Text('Rejeitar'),
                            ),
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('Pendente'),
                            ),
                            DropdownMenuItem(
                              value: 'notify',
                              child: Text('Notificar'),
                            ),
                          ],
                          onChanged: (value) {
                            _setStateAndPersist(() {
                              _offerBelowMinRentAction = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Gallery(ThemeData theme) {
    final imgCount = _totalSelectableImageCount();
    final wc = ThemeHelpers.borderColor(context);
    final badgeColor = imgCount >= _kMinGalleryImagesWeb &&
            imgCount <= _kMaxGalleryImagesWeb
        ? AppColors.status.success
        : AppColors.status.warning;

    Widget countBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
          ),
          child: Text(
            '$imgCount/$_kMinGalleryImagesWeb+',
            style: theme.textTheme.labelLarge?.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.collections_rounded,
            title: 'Fotos do imóvel',
            subtitle:
                'Entre $_kMinGalleryImagesWeb e $_kMaxGalleryImagesWeb imagens, como no cadastro web.',
            trailing: countBadge(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (imgCount < _kMinGalleryImagesWeb ||
                    imgCount > _kMaxGalleryImagesWeb) ...[
                  _wizardHintBanner(
                    theme,
                    accent: AppColors.status.warning,
                    icon: Icons.collections_outlined,
                    message: imgCount > _kMaxGalleryImagesWeb
                        ? 'Máximo $_kMaxGalleryImagesWeb imagens. Remova algumas para continuar.'
                        : 'São necessárias no mínimo $_kMinGalleryImagesWeb imagens para continuar o cadastro.',
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: wc.withValues(alpha: 0.85)),
                        ),
                        onPressed: _isUploadingImages ? null : _pickImages,
                        icon: _isUploadingImages
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _wizBrand(context),
                                ),
                              )
                            : Icon(
                                Icons.photo_library_rounded,
                                color: _wizBrand(context),
                              ),
                        label: Text(
                          _isUploadingImages ? 'Enviando…' : 'Da galeria',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: wc.withValues(alpha: 0.85)),
                        ),
                        onPressed: _isUploadingImages
                            ? null
                            : () async {
                                try {
                                  final XFile? photo =
                                      await _imagePicker.pickImage(
                                    source: ImageSource.camera,
                                    imageQuality: 85,
                                  );
                                  if (photo != null && mounted) {
                                    final croppedFile =
                                        await ImageCropHelper.cropImageSquare(
                                      context: context,
                                      imagePath: photo.path,
                                    );
                                    if (croppedFile != null && mounted) {
                                      setState(() {
                                        _selectedImages.add(croppedFile);
                                      });
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao tirar foto: $e'),
                                        backgroundColor:
                                            AppColors.status.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: Icon(
                          Icons.photo_camera_rounded,
                          color: _wizBrand(context),
                        ),
                        label: const Text('Câmera'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedImages.isEmpty && _uploadedImages.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _wizIsDark(context)
                            ? Colors.white.withValues(alpha: 0.12)
                            : wc.withValues(alpha: 0.55),
                      ),
                      color: _wizIsDark(context)
                          ? Colors.white.withValues(alpha: 0.04)
                          : wc.withValues(alpha: 0.03),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 44,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Nenhuma foto ainda',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use os botões acima para adicionar imagens.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _selectedImages.length + _uploadedImages.length,
                    itemBuilder: (context, index) {
                      if (index < _selectedImages.length) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _selectedImages[index],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                color: Colors.white,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(4),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedImages.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      }
                      final imageIndex = index - _selectedImages.length;
                      final image = _uploadedImages[imageIndex];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ShimmerImage(
                              imageUrl: image.url,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          if (image.isMain)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _wizBrand(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Capa',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              color: Colors.white,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                padding: const EdgeInsets.all(4),
                              ),
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                final response =
                                    await _galleryService.deleteImage(
                                  image.id,
                                );
                                if (!mounted) return;
                                if (response.success) {
                                  setState(() {
                                    _uploadedImages.removeAt(imageIndex);
                                  });
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        response.message ??
                                            'Erro ao remover imagem',
                                      ),
                                      backgroundColor:
                                          AppColors.status.error,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep6Clients(ThemeData theme) {
    final wc = ThemeHelpers.borderColor(context);
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.badge_rounded,
            title: 'Dados do proprietário',
            subtitle:
                'Nome e telefone são obrigatórios para enviar ao servidor (mesmo CRM web). Os demais campos são opcionais.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _ownerNameController,
                  label: 'Nome completo *',
                  hint: 'Nome como no documento',
                  maxLength: 255,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome do proprietário é obrigatório';
                    }
                    if (value.trim().length < 3) {
                      return 'Nome deve ter pelo menos 3 caracteres';
                    }
                    if (value.trim().length > 255) {
                      return 'Nome deve ter no máximo 255 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _ownerEmailController,
                  label: 'E-mail',
                  hint: 'email@exemplo.com',
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 255,
                  validator: (value) {
                    final t = value?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (t.length > 255) {
                      return 'Email deve ter no máximo 255 caracteres';
                    }
                    final emailRegex = RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    );
                    if (!emailRegex.hasMatch(t)) {
                      return 'Email inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _ownerPhoneController,
                        label: 'Telefone *',
                        hint: '(00) 00000-0000',
                        keyboardType: TextInputType.phone,
                        maxLength: 20,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Telefone do proprietário é obrigatório';
                          }
                          if (value.trim().length < 10) {
                            return 'Telefone deve ter pelo menos 10 caracteres';
                          }
                          if (value.trim().length > 20) {
                            return 'Telefone deve ter no máximo 20 caracteres';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _ownerDocumentController,
                        label: 'CPF / CNPJ',
                        hint: 'Documento',
                        maxLength: 18,
                        validator: (value) {
                          final digits =
                              value?.replaceAll(RegExp(r'\D'), '') ?? '';
                          if (digits.isEmpty) return null;
                          if (digits.length < 11 || digits.length > 18) {
                            return 'CPF/CNPJ: entre 11 e 18 dígitos';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _ownerAddressController,
                  label: 'Endereço de correspondência',
                  hint: 'Rua, número, cidade…',
                  maxLines: 2,
                  validator: (value) {
                    final t = value?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (t.length < 10) {
                      return 'Se informado, use um endereço mais descritivo';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.people_alt_rounded,
            title: 'Leads interessados',
            subtitle: 'Opcional — vincule quem já demonstrou interesse.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: wc.withValues(alpha: 0.85)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Seleção de clientes em breve'),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.person_add_rounded,
                    color: _wizBrand(context),
                  ),
                  label: const Text('Adicionar clientes'),
                ),
                if (_selectedClientIds.isEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: wc.withValues(alpha: 0.7)),
                      color: wc.withValues(alpha: 0.04),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 42,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Nenhum cliente vinculado',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Você pode associar mais tarde pela ficha do imóvel.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep7Review(ThemeData theme) {
    final onPrimary = Colors.white.withValues(alpha: 0.98);
    final g0 = Color.lerp(_wizCool(context), _wizBrand(context), 0.28)!;
    final g1 = _wizBrand(context);

    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
            icon: Icons.auto_awesome_rounded,
            title: 'Sugestões com IA',
            subtitle:
                'Combina tipo, local, medidas, valores e destaques do formulário.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isGeneratingDescription
                          ? null
                          : _generateDescription,
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [g0, g1],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isGeneratingDescription)
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: onPrimary,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: onPrimary,
                                ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _isGeneratingDescription
                                      ? 'Gerando sugestões…'
                                      : 'Gerar título e descrição',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _wizardHintBanner(
                  theme,
                  icon: Icons.fact_check_outlined,
                  message:
                      'Leia e ajuste o texto gerado nos campos seguintes antes de criar ou atualizar o imóvel.',
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.edit_note_rounded,
            title: 'Texto que vai ao ar',
            subtitle: 'Obrigatório nesta etapa — mesmo que a IA já tenha preenchido.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _titleController,
                  label: 'Título *',
                  hint: 'Ex: Casa com 3 quartos em condomínio fechado',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Título é obrigatório';
                    }
                    if (value.trim().length < 3) {
                      return 'Título deve ter pelo menos 3 caracteres';
                    }
                    if (value.trim().length > 255) {
                      return 'Título deve ter no máximo 255 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _descriptionController,
                  label: 'Descrição *',
                  hint: 'Descreva o imóvel em detalhes...',
                  maxLines: 8,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Descrição é obrigatória';
                    }
                    if (value.trim().length < 10) {
                      return 'Descrição deve ter pelo menos 10 caracteres';
                    }
                    if (value.trim().length > 5000) {
                      return 'Descrição deve ter no máximo 5000 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            icon: Icons.public_rounded,
            title: 'Disponibilidade e site',
            subtitle: !_approvalSettingsLoaded
                ? 'Carregando regras da empresa…'
                : (_requireApprovalToBeAvailable ||
                        _requireOwnerAuthorizationToBeAvailable ||
                        (_requireApprovalToPublishOnSite &&
                            (_publishToSite || !_listingStatusIsDraft)))
                    ? 'Esta empresa pode exigir fila de aprovação, autorização do proprietário e/ou aprovação de publicação — o backend define os status efetivos ao salvar, como no Intellisys web.'
                    : 'Escolha como o imóvel entra no CRM e se deseja solicitar publicação no site.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_approvalSettingsLoaded &&
                    !_requireApprovalToBeAvailable &&
                    !_requireOwnerAuthorizationToBeAvailable) ...[
                  Text(
                    'STATUS APÓS CADASTRO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      fontSize: 10,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Rascunho'),
                          icon: Icon(Icons.edit_note_outlined),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Disponível'),
                          icon: Icon(Icons.check_circle_outline),
                        ),
                      ],
                      selected: {_listingStatusIsDraft},
                      onSelectionChanged: (s) {
                        _setStateAndPersist(() {
                          _listingStatusIsDraft = s.first;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                _wizardSwitchRow(
                  theme,
                  icon: Icons.workspace_premium_rounded,
                  title: 'Destaque interno',
                  subtitle: 'Mesmo campo «destaque» do cadastro web.',
                  value: _isFeatured,
                  onChanged: (v) => _setStateAndPersist(() => _isFeatured = v),
                ),
                const SizedBox(height: 4),
                _wizardSwitchRow(
                  theme,
                  icon: Icons.public_rounded,
                  title: 'Publicar no site',
                  subtitle: _requireApprovalToPublishOnSite
                      ? 'Empresa pode exigir aprovação específica para publicação — o servidor reforça ao salvar.'
                      : 'Ao ativar: mínimo de $_kMinGalleryImagesWeb imagens e regras de status como no CRM web.',
                  value: _publishToSite,
                  onChanged: (v) => _setStateAndPersist(() => _publishToSite = v),
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            title: 'Resumo rápido',
            subtitle: 'Conferência antes de confirmar.',
            icon: Icons.inventory_2_rounded,
            child: _buildReviewSummary(theme),
          ),
        ],
      ),
    );
  }

  /// Ficha de revisão — agrupa o que está preenchido em metadados visuais
  /// (chips com ícone) em vez de empilhar muitos cards separados.
  Widget _buildReviewSummary(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);

    final loc = [
      _streetController.text.trim(),
      _numberController.text.trim().isNotEmpty
          ? ', ${_numberController.text.trim()}'
          : '',
      _neighborhoodController.text.trim().isNotEmpty
          ? ' · ${_neighborhoodController.text.trim()}'
          : '',
      _cityController.text.trim().isNotEmpty
          ? ' · ${_cityController.text.trim()}'
          : '',
      _stateController.text.trim().isNotEmpty
          ? '/${_stateController.text.trim()}'
          : '',
    ].join().trim();

    final beds = _bedroomsController.text.trim();
    final baths = _bathroomsController.text.trim();
    final suites = _suitesController.text.trim();
    final parking = _parkingSpacesController.text.trim();

    final salePrice = _salePriceController.text.trim();
    final rentPrice = _rentPriceController.text.trim();

    final totalImgs = _totalSelectableImageCount();

    final tiles = <_ReviewTileData>[
      _ReviewTileData(
        icon: Icons.home_rounded,
        label: 'Tipo',
        value: _selectedType.label,
      ),
      if (loc.isNotEmpty)
        _ReviewTileData(
          icon: Icons.place_rounded,
          label: 'Localização',
          value: loc,
        ),
      _ReviewTileData(
        icon: Icons.crop_square_rounded,
        label: 'Área total',
        value: _totalAreaController.text.isEmpty
            ? '—'
            : '${_totalAreaController.text} m²',
      ),
      if (_builtAreaController.text.isNotEmpty)
        _ReviewTileData(
          icon: Icons.architecture_rounded,
          label: 'Construída',
          value: '${_builtAreaController.text} m²',
        ),
      if (beds.isNotEmpty)
        _ReviewTileData(
          icon: Icons.bed_rounded,
          label: 'Quartos',
          value: beds,
        ),
      if (baths.isNotEmpty)
        _ReviewTileData(
          icon: Icons.bathtub_rounded,
          label: 'Banheiros',
          value: baths,
        ),
      if (suites.isNotEmpty)
        _ReviewTileData(
          icon: Icons.king_bed_rounded,
          label: 'Suítes',
          value: suites,
        ),
      if (parking.isNotEmpty)
        _ReviewTileData(
          icon: Icons.directions_car_rounded,
          label: 'Vagas',
          value: parking,
        ),
      if (salePrice.isNotEmpty)
        _ReviewTileData(
          icon: Icons.local_offer_rounded,
          label: 'Venda',
          value: 'R\$ $salePrice',
          accent: const Color(0xFF10B981),
        ),
      if (rentPrice.isNotEmpty)
        _ReviewTileData(
          icon: Icons.event_repeat_rounded,
          label: 'Aluguel',
          value: 'R\$ $rentPrice',
          accent: const Color(0xFF0EA5E9),
        ),
      _ReviewTileData(
        icon: Icons.collections_rounded,
        label: 'Fotos',
        value: '$totalImgs imagem(ns)',
        accent: const Color(0xFFA855F7),
      ),
      if (_selectedFeatures.isNotEmpty)
        _ReviewTileData(
          icon: Icons.star_rounded,
          label: 'Destaques',
          value: '${_selectedFeatures.length} marcado(s)',
        ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 460;
        final crossAxisCount = wide ? 2 : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 18,
          mainAxisSpacing: 14,
          childAspectRatio: wide ? 5.6 : 7.2,
          children: tiles.map((t) {
            final tone = t.accent ?? accent;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
                  ),
                  child: Icon(t.icon, size: 16, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          fontSize: 10,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  /// `_buildFormField` — campo de texto leve do wizard.
  /// O estilo (fill, borda, foco, padding) é todo herdado de `_wizardFieldTheme`,
  /// que envolve o conteúdo de cada `_wizardSection`. Aqui só ficam o label
  /// (acima do input) e os ajustes específicos do `TextFormField`.
  Widget _buildFormField(
    ThemeData theme, {
    required TextEditingController controller,
    String? label,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int? maxLength,
    TextCapitalization? textCapitalization,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLength: maxLength,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          inputFormatters: inputFormatters,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            suffixIcon: suffix,
            counterText: '',
          ),
        ),
      ],
    );
  }

  /// Footer minimalista com micro-progressão (linha tonal sutil) e ações limpas.
  Widget _buildNavigationButtons(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final accent = _stepAccent(_currentStep);
    final topLine = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.40);
    final progress =
        ((_currentStep + 1) / _totalSteps).clamp(0.0, 1.0).toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2A).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.96),
        border: Border(top: BorderSide(color: topLine)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isDark ? 18 : 12,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              child: SizedBox(
                height: 2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.30),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(accent, _wizCool(context), 0.25)!,
                              accent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : ThemeHelpers.borderColor(context)
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Voltar'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _currentStep < _totalSteps - 1
                        ? CustomButton(
                            text: 'Continuar',
                            onPressed: _nextStep,
                            icon: Icons.arrow_forward_rounded,
                          )
                        : widget.propertyId != null
                            ? CustomButton(
                                text: 'Salvar alterações',
                                onPressed:
                                    _isLoading ? null : () => _saveProperty(),
                                isLoading: _isLoading,
                                icon: Icons.check_rounded,
                              )
                            : CustomButton(
                                text: 'Finalizar cadastro',
                                onPressed: _isLoading
                                    ? null
                                    : () =>
                                        _saveProperty(saveAsDraft: false),
                                isLoading: _isLoading,
                                icon: Icons.check_rounded,
                              ),
                  ),
                ],
              ),
            ),
            if (_currentStep == _totalSteps - 1 &&
                widget.propertyId == null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _showSaveLocalDraftSheet,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        ThemeHelpers.textSecondaryColor(context),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: const Text('Salvar como rascunho local'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // Skeleton do indicador de etapas
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: SkeletonBox(height: 6, borderRadius: 999),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: SkeletonBox(height: 13, borderRadius: 4)),
                  const SizedBox(width: 12),
                  SkeletonBox(width: 44, height: 13, borderRadius: 4),
                ],
              ),
            ],
          ),
        ),

        // Skeleton do conteúdo do formulário
        Expanded(
          child: SingleChildScrollView(
            padding: _wizScrollPadding.subtract(const EdgeInsets.only(bottom: 4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Skeleton do título da etapa
                SkeletonText(
                  width: 200,
                  height: 24,
                  margin: const EdgeInsets.only(bottom: 24),
                ),

                // Skeleton dos campos de entrada
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonBox(
                  width: double.infinity,
                  height: 56,
                  borderRadius: 8,
                  margin: const EdgeInsets.only(bottom: 16),
                ),

                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonBox(
                  width: double.infinity,
                  height: 120,
                  borderRadius: 8,
                  margin: const EdgeInsets.only(bottom: 16),
                ),

                // Skeleton de campos em linha
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(
                            width: 100,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                          SkeletonBox(
                            width: double.infinity,
                            height: 56,
                            borderRadius: 8,
                            margin: const EdgeInsets.only(bottom: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(
                            width: 100,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                          SkeletonBox(
                            width: double.infinity,
                            height: 56,
                            borderRadius: 8,
                            margin: const EdgeInsets.only(bottom: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Skeleton de chips (tipo de imóvel, etc.)
                SkeletonText(
                  width: 150,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8, top: 8),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(4, (index) {
                    return SkeletonBox(
                      width: 100,
                      height: 32,
                      borderRadius: 16,
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // Skeleton de mais campos
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonBox(
                  width: double.infinity,
                  height: 56,
                  borderRadius: 8,
                  margin: const EdgeInsets.only(bottom: 16),
                ),

                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonBox(
                  width: double.infinity,
                  height: 56,
                  borderRadius: 8,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
              ],
            ),
          ),
        ),

        // Skeleton dos botões de navegação
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              top: BorderSide(
                color: ThemeHelpers.borderColor(context).withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(child: SkeletonBox(height: 48, borderRadius: 14)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SkeletonBox(height: 48, borderRadius: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Resultado de uma validação multi-step — reporta em qual etapa e qual o
/// motivo, para guiar o usuário ao primeiro problema.
class _StepValidationFailure {
  final int step;
  final String message;

  const _StepValidationFailure({required this.step, required this.message});
}

/// Dados de uma micro-ficha do resumo final (`_buildReviewSummary`).
class _ReviewTileData {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  const _ReviewTileData({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });
}
