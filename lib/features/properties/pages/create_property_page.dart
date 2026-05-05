import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
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
import '../../../../core/routes/app_routes.dart';
import '../models/property_local_draft.dart';
import '../models/property_wizard_pop_result.dart';
import '../services/property_local_draft_storage.dart';
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
      EdgeInsets.fromLTRB(24, 18, 24, 52);
  static const double _wizGapAfterHeader = 28;
  static const double _wizGapBetweenSections = 22;

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
          // Abrir crop de imagem (formato retangular livre para imagens de imóvel)
          final croppedFile = await ImageCropHelper.cropImageRect(
            imagePath: photo.path,
            compressQuality: 85,
          );
          
          if (croppedFile != null && mounted) {
            setState(() {
              _selectedImages.add(croppedFile);
            });
          } else if (croppedFile == null && mounted) {
            // Usuário cancelou o crop, mas mantém a imagem original
            setState(() {
              _selectedImages.add(File(photo.path));
            });
          }
        }
      } else {
        // Selecionar múltiplas imagens da galeria
        final List<XFile> images = await _imagePicker.pickMultiImage(
          imageQuality: 85,
        );
        if (images.isNotEmpty && mounted) {
          // Processar cada imagem com crop individualmente
          for (final xFile in images) {
            if (!mounted) break;
            
            // Abrir crop de imagem (formato retangular livre para imagens de imóvel)
            final croppedFile = await ImageCropHelper.cropImageRect(
              imagePath: xFile.path,
              compressQuality: 85,
            );
            
            if (croppedFile != null && mounted) {
              setState(() {
                _selectedImages.add(croppedFile);
              });
            } else if (croppedFile == null && mounted) {
              // Usuário cancelou o crop, mas mantém a imagem original
              setState(() {
                _selectedImages.add(File(xFile.path));
              });
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
      setState(() {
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
      final id = _activeLocalDraftId ??
          'ld_${DateTime.now().millisecondsSinceEpoch}';

      final paths = await _draftStorage.copyImagesToDraftFolder(
        draftId: id,
        sources: List<File>.from(_selectedImages),
      );

      final draft = PropertyLocalDraft(
        id: id,
        displayTitle: trimmed,
        companyId: companyId,
        updatedAt: DateTime.now(),
        wizardStep: _currentStep.clamp(0, _totalSteps - 1),
        formJson: _freezeFormState(),
        imagePaths: paths,
      );

      await _draftStorage.save(draft);

      if (mounted) {
        setState(() {
          _activeLocalDraftId = id;
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
                Text('Rascunho «$trimmed» guardado neste dispositivo.'),
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
      setState(() {
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

  bool _validatePublicationRules({
    required bool saveAsDraft,
    required String resolvedStatus,
  }) {
    if (!_publishToSite) return true;

    if (saveAsDraft) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Desative «Publicar no site» ao salvar como rascunho (regra igual ao sistema web).',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
      return false;
    }

    final imgCount = _totalSelectableImageCount();
    if (imgCount < _kMinGalleryImagesWeb || imgCount > _kMaxGalleryImagesWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Publicação no site exige entre $_kMinGalleryImagesWeb e $_kMaxGalleryImagesWeb '
              'imagens (atual: $imgCount).',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
      return false;
    }

    // Paridade CreatePropertyPage web: só «Disponível» bloqueia se não há
    // `requireApprovalToBeAvailable` (linha ~3204 do CreatePropertyPage.tsx).
    final needsAvailableResolved = !_requireApprovalToBeAvailable;
    if (needsAvailableResolved && resolvedStatus != 'available') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Apenas imóveis com status «Disponível» podem ser publicados no site '
              '(quando a empresa não exige apenas a fila de aprovação).',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _saveProperty({bool saveAsDraft = false}) async {
    if (!_formKey.currentState!.validate()) {
      _pageController.jumpToPage(0);
      setState(() {
        _currentStep = 0;
      });
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
    if (!_validatePublicationRules(
      saveAsDraft: saveAsDraft,
      resolvedStatus: resolvedStatus,
    )) {
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

      final cfgErr = configurableFieldsErrorPt(_formRequiredKeys, data);
      if (cfgErr != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(cfgErr),
              backgroundColor: AppColors.status.error,
            ),
          );
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
                              ? 'Cadastro registrado — o imóvel segue para a mesma '
                                    'fila de aprovação/autorização do sistema.'
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao salvar propriedade'),
              backgroundColor: AppColors.status.error,
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

  /// Fundo contínuo com profundidade — evita “painel preto + vermelho” no dark.
  BoxDecoration _wizardBackdropDecoration(BuildContext context) {
    final isDark = _wizIsDark(context);
    if (isDark) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.32, 0.62, 1.0],
          colors: [
            const Color(0xFF17172A),
            const Color(0xFF1E1E38),
            const Color(0xFF25244A),
            const Color(0xFF151520),
          ],
        ),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.55, 1.0],
        colors: [
          AppColors.background.background,
          Color.lerp(AppColors.background.backgroundSecondary,
              AppColors.background.backgroundTertiary, 0.5)!,
          const Color(0xFFF1F6FC),
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

  Widget _buildStepIndicator(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final progress = (_currentStep + 1) / _totalSteps;
    final track = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.28);

    final gradColors = isDark
        ? [
            _wizCool(context).withValues(alpha: 0.75),
            _wizBrand(context).withValues(alpha: 0.88),
          ]
        : [
            _wizCool(context).withValues(alpha: 0.82),
            _wizBrand(context),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: track),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradColors),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _wizardTitles[_currentStep.clamp(0, _totalSteps - 1)],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                  letterSpacing: 0.15,
                ),
              ),
              Text(
                '${_currentStep + 1}/$_totalSteps',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _wizBrand(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wizardStepHeader(ThemeData theme) {
    final step = _currentStep.clamp(0, _totalSteps - 1);
    final isDark = _wizIsDark(context);
    final cool = _wizCool(context);
    final brand = _wizBrand(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      cool.withValues(alpha: 0.22),
                      brand.withValues(alpha: 0.14),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      cool.withValues(alpha: 0.08),
                    ],
            ),
            border: Border.all(
              color: cool.withValues(alpha: isDark ? 0.38 : 0.22),
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: cool.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Text(
            'Etapa ${step + 1} de $_totalSteps',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? cool : _wizBrandMuted(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _wizardTitles[step],
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.35,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _wizardSubtitles[step],
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.45,
            fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) + 0.25,
          ),
        ),
      ],
    );
  }

  Widget _wizardSection(
    ThemeData theme, {
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final isDark = _wizIsDark(context);
    final bc = ThemeHelpers.borderColor(context);
    final cool = _wizCool(context);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : bc.withValues(alpha: 0.34);

    final deco = BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: isDark
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.07),
                const Color(0xFF28283E).withValues(alpha: 0.92),
                Color.lerp(const Color(0xFF303052), const Color(0xFF28283E), 0.5)!
                    .withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.45, 1.0],
            )
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.93),
                const Color(0xFFF9FBFE),
              ],
            ),
      border: Border.all(color: borderColor),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: cool.withValues(alpha: 0.09),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]
          : [
              BoxShadow(
                color: _wizBrand(context).withValues(alpha: 0.035),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: ThemeHelpers.shadowColor(context),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
    );

    return DecoratedBox(
      decoration: deco,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 21, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            height: 1.42,
                            fontSize:
                                (theme.textTheme.bodySmall?.fontSize ?? 12) +
                                    0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
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

  ChipThemeData _wizardChipTheme(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final cool = _wizCool(context);
    final brand = _wizBrand(context);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.4);

    return ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: border),
      showCheckmark: false,
      selectedColor: isDark
          ? Color.lerp(cool.withValues(alpha: 0.28), brand.withValues(alpha: 0.15), 0.5)!
          : brand.withValues(alpha: 0.12),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.white.withValues(alpha: 0.65),
      labelStyle:
          theme.textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _wizardOutlinedFieldDecoration(String labelText) {
    final isDark = _wizIsDark(context);
    final soft = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.38);

    final focusBlend = Color.lerp(_wizCool(context), _wizBrand(context), 0.45)!;

    return InputDecoration(
      labelText: labelText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: soft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: focusBlend, width: isDark ? 1.85 : 1.6),
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
            title: 'Gerar texto com IA',
            subtitle:
                'Na última etapa você pode criar ou ajustar título e descrição automaticamente.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _wizCool(context).withValues(alpha: 0.28),
                        _wizBrand(context).withValues(alpha: 0.22),
                      ],
                    ),
                    border: Border.all(
                      color: _wizCool(context).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Color.lerp(_wizCool(context), Colors.white, 0.45),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preencher título e descrição na revisão',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchTheme(
                        data: SwitchThemeData(
                          overlayColor:
                              WidgetStateProperty.all(Colors.transparent),
                          trackOutlineWidth:
                              WidgetStateProperty.resolveWith((states) => 1),
                          trackOutlineColor: WidgetStateProperty.resolveWith(
                            (states) => ThemeHelpers.borderColor(context),
                          ),
                          thumbColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return _wizBrand(context);
                            }
                            return ThemeHelpers.borderColor(context);
                          }),
                          trackColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Color.lerp(
                                _wizCool(context),
                                _wizBrand(context),
                                0.35,
                              )!.withValues(alpha: 0.55);
                            }
                            return _wizIsDark(context)
                                ? Colors.white.withValues(alpha: 0.08)
                                : null;
                          }),
                        ),
                        child: Transform.scale(
                          scale: 0.92,
                          alignment: Alignment.centerLeft,
                          child: Switch.adaptive(
                            value: _autoGenerateOnReview,
                            onChanged: (value) {
                              setState(() {
                                _autoGenerateOnReview = value;
                              });
                            },
                          ),
                        ),
                      ),
                      Text(
                        _autoGenerateOnReview
                            ? 'Ao final, a IA usa os dados do formulário para sugerir título e descrição.'
                            : 'Informe manualmente aqui ou use o botão de IA na etapa final.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
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
            title: 'Tipo de imóvel *',
            subtitle: 'Escolha a categoria que melhor representa o anúncio.',
            child: Theme(
              data: theme.copyWith(chipTheme: _wizardChipTheme(theme)),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: PropertyType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedType = type);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          if (_formRequiredKeys.contains('teamId') || _formTeams.isNotEmpty) ...[
            SizedBox(height: _wizGapBetweenSections),
            _wizardSection(
              theme,
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
                      value: _selectedTeamId,
                      decoration: InputDecoration(
                        labelText: 'Selecionar equipe',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                          : (v) => setState(() => _selectedTeamId = v),
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
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
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
          if (_formRequiredKeys.contains('condominiumId') ||
              _formRequiredKeys.contains('empreendimentoId') ||
              _condominiumOptions.isNotEmpty ||
              _empreendimentoOptions.isNotEmpty ||
              (_selectedCondominiumId != null &&
                  _selectedCondominiumId!.isNotEmpty) ||
              (_selectedEmpreendimentoId != null &&
                  _selectedEmpreendimentoId!.isNotEmpty)) ...[
            SizedBox(height: _wizGapBetweenSections),
            _wizardSection(
              theme,
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
                      value: _selectedCondominiumId,
                      decoration: InputDecoration(
                        labelText: _formRequiredKeys.contains('condominiumId')
                            ? 'Condomínio *'
                            : 'Condomínio',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                                  setState(() => _selectedCondominiumId = v),
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
                      value: _selectedEmpreendimentoId,
                      decoration: InputDecoration(
                        labelText:
                            _formRequiredKeys.contains('empreendimentoId')
                                ? 'Empreendimento *'
                                : 'Empreendimento',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                              setState(() => _selectedEmpreendimentoId = v),
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
            title: 'Destaques e comodidades',
            subtitle:
                'Toque para marcar — ajudam filtros internos e a descrição com IA.',
            child: Theme(
              data: theme.copyWith(
                chipTheme: _wizardChipTheme(theme).copyWith(
                  showCheckmark: true,
                ),
              ),
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
                          setState(() {
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
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Values(ThemeData theme) {
    final track = _wizIsDark(context)
        ? const Color(0xFF2A2A44).withValues(alpha: 0.55)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.06);
    return SingleChildScrollView(
      padding: _wizScrollPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wizardStepHeader(theme),
          SizedBox(height: _wizGapAfterHeader),
          _wizardSection(
            theme,
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
            title: 'Negociação',
            subtitle: 'Opcional — ative para registrar mínimos e respostas automáticas.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _wizIsDark(context)
                          ? Colors.white.withValues(alpha: 0.08)
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.22),
                    ),
                  ),
                  child: Theme(
                    data: theme.copyWith(
                      switchTheme: SwitchThemeData(
                        thumbColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _wizBrand(context);
                          }
                          return null;
                        }),
                        trackColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Color.lerp(
                              _wizCool(context),
                              _wizBrand(context),
                              0.28,
                            )!.withValues(alpha: 0.45);
                          }
                          return null;
                        }),
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        'Aceita negociação',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Permite ofertas entre o valor anunciado e o mínimo definido.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.35,
                        ),
                      ),
                      value: _acceptsNegotiation,
                      onChanged: (value) =>
                          setState(() => _acceptsNegotiation = value),
                    ),
                  ),
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
                    'Se receber uma oferta abaixo do mínimo',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _offerBelowMinSaleAction,
                          decoration:
                              _wizardOutlinedFieldDecoration('Canal — venda'),
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
                            setState(() {
                              _offerBelowMinSaleAction = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _offerBelowMinRentAction,
                          decoration: _wizardOutlinedFieldDecoration(
                            'Canal — aluguel',
                          ),
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
                            setState(() {
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
                                        await ImageCropHelper.cropImageRect(
                                      imagePath: photo.path,
                                      compressQuality: 85,
                                    );

                                    if (croppedFile != null && mounted) {
                                      setState(() {
                                        _selectedImages.add(croppedFile);
                                      });
                                    } else if (croppedFile == null && mounted) {
                                      setState(() {
                                        _selectedImages.add(File(photo.path));
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
                    'Status após cadastro',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
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
                      setState(() {
                        _listingStatusIsDraft = s.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Destaque interno'),
                  subtitle: Text(
                    'Mesmo campo «destaque» do cadastro web.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  value: _isFeatured,
                  onChanged: (v) => setState(() => _isFeatured = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicar no site'),
                  subtitle: Text(
                    _requireApprovalToPublishOnSite
                        ? 'Empresa pode exigir aprovação específica para publicação — o servidor reforça ao salvar.'
                        : 'Ao ativar: mínimo de $_kMinGalleryImagesWeb imagens e regras de status como no CRM web.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  value: _publishToSite,
                  onChanged: (v) => setState(() => _publishToSite = v),
                ),
              ],
            ),
          ),
          SizedBox(height: _wizGapBetweenSections),
          _wizardSection(
            theme,
            title: 'Resumo rápido',
            subtitle: 'Use como checklist antes de confirmar.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReviewCard(theme, 'Tipo', _selectedType.label),
                const SizedBox(height: 10),
                _buildReviewCard(
                  theme,
                  'Localização',
                  '${_streetController.text}, ${_numberController.text} · ${_neighborhoodController.text}, ${_cityController.text} · ${_stateController.text}',
                ),
                const SizedBox(height: 10),
                _buildReviewCard(
                  theme,
                  'Área total',
                  '${_totalAreaController.text} m²',
                ),
                if (_builtAreaController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    theme,
                    'Área construída',
                    '${_builtAreaController.text} m²',
                  ),
                ],
                if (_bedroomsController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildReviewCard(theme, 'Quartos', _bedroomsController.text),
                ],
                if (_bathroomsController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    theme,
                    'Banheiros',
                    _bathroomsController.text,
                  ),
                ],
                if (_salePriceController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    theme,
                    'Venda',
                    'R\$ ${_salePriceController.text}',
                  ),
                ],
                if (_rentPriceController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    theme,
                    'Aluguel',
                    'R\$ ${_rentPriceController.text}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ThemeData theme, String label, String value) {
    final isDark = _wizIsDark(context);
    final cool = _wizCool(context);
    final strip = Color.lerp(cool, _wizBrand(context), 0.35)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.02),
                ],
              )
            : null,
        color: isDark ? null : Colors.white.withValues(alpha: 0.55),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.only(right: 14, top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cool.withValues(alpha: 0.95),
                  strip.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLength: maxLength,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          inputFormatters: inputFormatters,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            prefixText: prefixText,
            suffixIcon: suffix,
            counterText: '',
            filled: true,
            fillColor: _wizIsDark(context)
                ? Colors.white.withValues(alpha: 0.056)
                : Colors.white.withValues(alpha: 0.72),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _wizIsDark(context)
                    ? Colors.white.withValues(alpha: 0.13)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Color.lerp(
                      _wizCool(context),
                      _wizBrand(context),
                      0.45,
                    ) ??
                    _wizBrand(context),
                width: _wizIsDark(context) ? 1.85 : 1.55,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(ThemeData theme) {
    final isDark = _wizIsDark(context);
    final topLine = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF24243A).withValues(alpha: 0.92),
                  const Color(0xFF1E1E30).withValues(alpha: 0.97),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.97),
                  Color.lerp(Colors.white, _wizCool(context), 0.04)!,
                ],
              ),
        border: Border(
          top: BorderSide(color: topLine),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : _wizBrand(context).withValues(alpha: 0.04),
            blurRadius: isDark ? 22 : 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _previousStep,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text('Voltar'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 14),
              Expanded(
                flex: _currentStep > 0 ? 2 : 1,
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
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomButton(
                                text: 'Finalizar cadastro',
                                onPressed: _isLoading
                                    ? null
                                    : () =>
                                        _saveProperty(saveAsDraft: false),
                                isLoading: _isLoading,
                                icon: Icons.check_rounded,
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _isLoading
                                    ? null
                                    : _showSaveLocalDraftSheet,
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : ThemeHelpers.borderColor(context)
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Text('Rascunho local · nomear e guardar'),
                              ),
                            ],
                          ),
              ),
            ],
          ),
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
