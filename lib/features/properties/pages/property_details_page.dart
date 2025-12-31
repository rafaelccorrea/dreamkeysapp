import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../widgets/property_public_toggle.dart';
import '../../matches/widgets/matches_badge.dart';
import '../../../../core/routes/app_routes.dart';
import '../../documents/services/document_service.dart';
import '../../documents/models/document_model.dart';
import '../../clients/services/client_service.dart';
import '../../documents/widgets/entity_selector.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../shared/services/api_service.dart';
import '../../keys/services/key_service.dart';
import '../../keys/models/key_model.dart' as key_models;
import 'package:flutter/foundation.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Página de detalhes da propriedade
class PropertyDetailsPage extends StatefulWidget {
  final String propertyId;

  const PropertyDetailsPage({super.key, required this.propertyId});

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  final PropertyService _propertyService = PropertyService.instance;
  final DocumentService _documentService = DocumentService.instance;
  final ClientService _clientService = ClientService.instance;
  final ApiService _apiService = ApiService.instance;
  final KeyService _keyService = KeyService.instance;
  bool _isLoading = true;
  Property? _property;
  String? _errorMessage;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  // Documentos
  List<Document> _documents = [];
  bool _isLoadingDocuments = false;

  // Checklists
  List<dynamic> _checklists = [];
  bool _isLoadingChecklists = false;

  // Despesas
  List<dynamic> _expenses = [];
  bool _isLoadingExpenses = false;
  Map<String, dynamic>? _expensesSummary;

  // Chaves
  List<key_models.Key> _keys = [];
  bool _isLoadingKeys = false;

  @override
  void initState() {
    super.initState();
    _loadProperty();
  }

  Future<void> _loadDocuments() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingDocuments = true;
    });

    try {
      final response = await _documentService.getDocuments(
        filters: DocumentFilters(propertyId: widget.propertyId),
        page: 1,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          _isLoadingDocuments = false;
          if (response.success && response.data != null) {
            _documents = response.data!.data;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro ao carregar documentos: $e');
      if (mounted) {
        setState(() {
          _isLoadingDocuments = false;
        });
      }
    }
  }

  Future<void> _loadChecklists() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingChecklists = true;
    });

    try {
      final response = await _apiService.get<dynamic>(
        ApiConstants.saleChecklistsByProperty(widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingChecklists = false;
          if (response.success && response.data != null) {
            if (response.data is List) {
              _checklists = response.data as List<dynamic>;
            } else if (response.data is Map<String, dynamic>) {
              final data = response.data as Map<String, dynamic>;
              _checklists =
                  data['checklists'] as List<dynamic>? ??
                  data['data'] as List<dynamic>? ??
                  [];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro ao carregar checklists: $e');
      if (mounted) {
        setState(() {
          _isLoadingChecklists = false;
        });
      }
    }
  }

  Future<void> _loadExpenses() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingExpenses = true;
    });

    try {
      // Carregar lista de despesas
      final expensesResponse = await _apiService.get<dynamic>(
        ApiConstants.propertyExpenses(widget.propertyId),
      );

      // Carregar resumo de despesas
      final summaryResponse = await _apiService.get<dynamic>(
        ApiConstants.propertyExpensesSummary(widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingExpenses = false;
          if (expensesResponse.success && expensesResponse.data != null) {
            if (expensesResponse.data is List) {
              _expenses = expensesResponse.data as List<dynamic>;
            } else if (expensesResponse.data is Map<String, dynamic>) {
              final data = expensesResponse.data as Map<String, dynamic>;
              _expenses =
                  data['data'] as List<dynamic>? ??
                  data['expenses'] as List<dynamic>? ??
                  [];
            }
          }
          if (summaryResponse.success && summaryResponse.data != null) {
            _expensesSummary = summaryResponse.data as Map<String, dynamic>;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro ao carregar despesas: $e');
      if (mounted) {
        setState(() {
          _isLoadingExpenses = false;
        });
      }
    }
  }

  Future<void> _loadKeys() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingKeys = true;
    });

    try {
      // Carregar lista de chaves usando KeyService
      final keysResponse = await _keyService.getKeys(
        filters: key_models.KeyFilters(propertyId: widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingKeys = false;
          if (keysResponse.success && keysResponse.data != null) {
            _keys = keysResponse.data!;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro ao carregar chaves: $e');
      if (mounted) {
        setState(() {
          _isLoadingKeys = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  Future<void> _loadProperty() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _propertyService.getPropertyById(
        widget.propertyId,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _property = response.data;
            _isLoading = false;
          });
          // Carregar dados relacionados após carregar propriedade
          _loadDocuments();
          _loadChecklists();
          _loadExpenses();
          _loadKeys();
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar propriedade';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteProperty() async {
    if (_property == null) return;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Excluir Propriedade',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tem certeza que deseja excluir "${_property!.title}"? Esta ação não pode ser desfeita.',
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.delete),
                        label: const Text('Excluir Propriedade'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.status.error,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      final response = await _propertyService.deleteProperty(widget.propertyId);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Propriedade excluída com sucesso')),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir propriedade'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Detalhes do Imóvel',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        if (_property != null && _property!.hasPendingOffers == true)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.request_quote),
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/properties/offers',
                    arguments: {'propertyId': widget.propertyId},
                  );
                },
                tooltip: 'Ver Ofertas',
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                Navigator.of(
                  context,
                ).pushNamed('/properties/${widget.propertyId}/edit');
                break;
              case 'delete':
                _deleteProperty();
                break;
              case 'offers':
                Navigator.of(context).pushNamed(
                  '/properties/offers',
                  arguments: {'propertyId': widget.propertyId},
                );
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            if (_property != null && _property!.hasPendingOffers == true)
              const PopupMenuItem(
                value: 'offers',
                child: Row(
                  children: [
                    Icon(Icons.request_quote, size: 20),
                    SizedBox(width: 8),
                    Text('Ver Ofertas'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : _property != null
          ? _buildPropertyDetails(context, theme, _property!)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton da imagem
          SkeletonBox(width: double.infinity, height: 300, borderRadius: 0),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  width: 250,
                  height: 24,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonText(
                  width: 200,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 20),
                ),
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 20),
                ),
                SkeletonText(
                  width: 150,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
                SkeletonCard(
                  height: 200,
                  child: Column(
                    children: List.generate(
                      4,
                      (index) => Padding(
                        padding: EdgeInsets.only(bottom: index < 3 ? 16 : 0),
                        child: Row(
                          children: [
                            SkeletonBox(
                              width: 24,
                              height: 24,
                              borderRadius: 12,
                            ),
                            const SizedBox(width: 12),
                            SkeletonText(width: 100, height: 16),
                            const Spacer(),
                            SkeletonText(width: 80, height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar propriedade',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProperty,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyDetails(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Galeria de imagens
          _buildImageGallery(context, property),

          // Conteúdo principal
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título e código
                MatchesBadge(
                  propertyId: widget.propertyId,
                  onClick: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.matchesByProperty(widget.propertyId),
                    );
                  },
                  child: Text(
                    property.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                if (property.code != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Código: ${property.code}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Endereço
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        property.address.isNotEmpty
                            ? property.address
                            : '${property.street}, ${property.number} - ${property.neighborhood}, ${property.city} - ${property.state}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      property.status,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    property.status.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _getStatusColor(property.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Preço (destaque melhorado)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.primary.withValues(alpha: 0.15),
                        AppColors.primary.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.primary.withValues(
                          alpha: 0.15,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label do tipo de operação
                      Row(
                        children: [
                          Icon(
                            property.salePrice != null
                                ? Icons.sell
                                : Icons.home,
                            size: 20,
                            color: AppColors.primary.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            property.salePrice != null ? 'VENDA' : 'ALUGUEL',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary.primary,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Preço principal (maior e mais destacado)
                      if (property.salePrice != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'R\$',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary.primary,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _currencyFormatter
                                    .format(property.salePrice)
                                    .replaceAll('R\$', '')
                                    .trim(),
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary.primary,
                                  fontSize: 42,
                                  height: 1.1,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (property.rentPrice != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'R\$',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary.primary,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _currencyFormatter
                                    .format(property.rentPrice)
                                    .replaceAll('R\$', '')
                                    .trim(),
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary.primary,
                                  fontSize: 42,
                                  height: 1.1,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '/mês',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary.primary.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Características principais
                _buildSectionTitle(theme, 'Características'),
                const SizedBox(height: 16),
                _buildCharacteristicsCard(context, theme, property),
                const SizedBox(height: 32),

                // Descrição
                _buildSectionTitle(theme, 'Descrição'),
                const SizedBox(height: 16),
                Text(
                  property.description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Informações adicionais
                if (property.condominiumFee != null ||
                    property.iptu != null) ...[
                  _buildSectionTitle(theme, 'Valores Adicionais'),
                  const SizedBox(height: 16),
                  _buildAdditionalValuesCard(context, theme, property),
                  const SizedBox(height: 32),
                ],

                // Localização no mapa
                _buildSectionTitle(theme, 'Localização'),
                const SizedBox(height: 16),
                _buildMapSection(context, theme, property),
                const SizedBox(height: 32),

                // Recursos/Comodidades
                if (property.features.isNotEmpty) ...[
                  _buildSectionTitle(theme, 'Recursos e Comodidades'),
                  const SizedBox(height: 16),
                  _buildFeaturesSection(context, theme, property.features),
                  const SizedBox(height: 32),
                ],

                // Status da Chave (Seção 6)
                _buildSectionTitle(theme, 'Status da Chave'),
                const SizedBox(height: 16),
                _buildKeyStatusSection(context, theme, property),
                const SizedBox(height: 32),

                // Clientes Vinculados (Seção 7)
                _buildSectionTitle(theme, 'Clientes Vinculados'),
                const SizedBox(height: 16),
                _buildClientsSection(context, theme, property),
                const SizedBox(height: 32),

                // Despesas do Imóvel (Seção 8)
                _buildSectionTitle(theme, 'Despesas do Imóvel'),
                const SizedBox(height: 16),
                _buildExpensesSection(context, theme, property),
                const SizedBox(height: 32),

                // Checklists (Seção 9)
                _buildSectionTitle(theme, 'Checklists'),
                const SizedBox(height: 16),
                _buildChecklistsSection(context, theme, property),
                const SizedBox(height: 32),

                // Documentos (Seção 10)
                _buildSectionTitle(theme, 'Documentos'),
                const SizedBox(height: 16),
                _buildDocumentsSection(context, theme, property),
                const SizedBox(height: 32),

                // Publicação no site (Seção 11)
                _buildSectionTitle(theme, 'Publicação'),
                const SizedBox(height: 16),
                PropertyPublicToggle(
                  propertyId: property.id,
                  initialValue: property.isAvailableForSite ?? false,
                  propertyStatus: property.status,
                  isActive: property.isActive,
                  imageCount:
                      property.imageCount ?? property.images?.length ?? 0,
                  onSuccess: () {
                    _loadProperty(); // Recarregar dados
                  },
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        backgroundColor: AppColors.status.error,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Ofertas (Seção 12)
                if (property.hasPendingOffers == true ||
                    property.totalOffersCount != null &&
                        property.totalOffersCount! > 0) ...[
                  _buildSectionTitle(theme, 'Ofertas'),
                  const SizedBox(height: 16),
                  _buildOffersSection(context, theme, property),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery(BuildContext context, Property property) {
    final images = property.images ?? [];
    final theme = Theme.of(context);

    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        height: 300,
        color: theme.brightness == Brightness.dark
            ? AppColors.background.backgroundSecondaryDarkMode
            : AppColors.background.backgroundSecondary,
        child: Icon(
          Icons.home_outlined,
          size: 64,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      );
    }

    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          PageView.builder(
            controller: _imagePageController,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final image = images[index];
              return ShimmerImage(
                imageUrl: image.url,
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                errorWidget: Container(
                  color: AppColors.background.backgroundSecondary,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              );
            },
          ),
          // Seta esquerda (anterior)
          if (images.length > 1 && _currentImageIndex > 0)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _imagePageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_left,
                      color: AppColors.primary.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          // Seta direita (próxima)
          if (images.length > 1 && _currentImageIndex < images.length - 1)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _imagePageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.primary.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textColor(context),
      ),
    );
  }

  Widget _buildCharacteristicsCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCharacteristicRow(
              theme,
              Icons.home_outlined,
              'Tipo',
              property.type.label,
            ),
            if (property.totalArea > 0)
              _buildCharacteristicRow(
                theme,
                Icons.square_foot,
                'Área Total',
                '${property.totalArea.toInt()} m²',
              ),
            if (property.builtArea != null && property.builtArea! > 0)
              _buildCharacteristicRow(
                theme,
                Icons.business,
                'Área Construída',
                '${property.builtArea!.toInt()} m²',
              ),
            if (property.bedrooms != null)
              _buildCharacteristicRow(
                theme,
                Icons.bed,
                'Quartos',
                '${property.bedrooms}',
              ),
            if (property.bathrooms != null)
              _buildCharacteristicRow(
                theme,
                Icons.bathtub_outlined,
                'Banheiros',
                '${property.bathrooms}',
              ),
            if (property.parkingSpaces != null)
              _buildCharacteristicRow(
                theme,
                Icons.local_parking,
                'Vagas',
                '${property.parkingSpaces}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacteristicRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalValuesCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (property.condominiumFee != null)
              _buildCharacteristicRow(
                theme,
                Icons.apartment,
                'Condomínio',
                _currencyFormatter.format(property.condominiumFee),
              ),
            if (property.iptu != null)
              _buildCharacteristicRow(
                theme,
                Icons.receipt,
                'IPTU',
                _currencyFormatter.format(property.iptu),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffersSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ofertas Recebidas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/properties/offers',
                      arguments: {'propertyId': property.id},
                    );
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Ver Todas'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (property.totalOffersCount != null) ...[
              _buildInfoRow(theme, 'Total', '${property.totalOffersCount}'),
              if (property.pendingOffersCount != null)
                _buildInfoRow(
                  theme,
                  'Pendentes',
                  '${property.pendingOffersCount}',
                ),
              if (property.acceptedOffersCount != null)
                _buildInfoRow(
                  theme,
                  'Aceitas',
                  '${property.acceptedOffersCount}',
                ),
              if (property.rejectedOffersCount != null)
                _buildInfoRow(
                  theme,
                  'Rejeitadas',
                  '${property.rejectedOffersCount}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStatusSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, color: AppColors.primary.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status da Chave',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Visualize e gerencie chaves vinculadas a esta propriedade',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingKeys)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_keys.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.vpn_key_outlined,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma chave cadastrada',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showCreateKeyModal(context, property);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Criar Chave'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  ...(_keys.map((key) {
                    final statusColor =
                        key.status == key_models.KeyStatus.available
                        ? AppColors.status.success
                        : key.status == key_models.KeyStatus.inUse
                        ? AppColors.status.warning
                        : AppColors.status.error;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.background.backgroundSecondaryDarkMode
                            : AppColors.background.backgroundSecondary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: ThemeHelpers.borderLightColor(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.vpn_key, color: statusColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  key.name,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (key.location != null &&
                                    key.location!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Localização: ${key.location}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                                ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tipo: ${key.type.label}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              key.status.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditKeyModal(context, property, key);
                              } else if (value == 'delete') {
                                _deleteKey(
                                  context,
                                  property.id,
                                  key.id,
                                  key.name,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('Editar'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Excluir',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  })),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _showCreateKeyModal(context, property);
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Criar Chave'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final clients = property.clients ?? [];
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.people,
                        color: AppColors.primary.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Clientes Vinculados',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (clients.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${clients.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    _showLinkClientModal(context, property);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (clients.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum cliente vinculado',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...clients.map((client) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.clientDetails(client.id));
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            client.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (client.email.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  client.email,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                              if (client.phone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  client.phone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                client.interestType,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: AppColors.primary.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Despesas do Imóvel',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    _showCreateExpenseModal(context, property);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingExpenses)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_expenses.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma despesa cadastrada',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Resumo de Despesas
              if (_expensesSummary != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pendentes',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalPending'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vencidas',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalOverdue'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.status.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pagas',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalPaid'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.status.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Pendente',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currencyFormatter.format(
                                    ((_expensesSummary!['totalPendingAmount'] ??
                                                0)
                                            as num)
                                        .toDouble(),
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              // Lista de Despesas
              ...(_expenses.take(5).map((expense) {
                final exp = expense as Map<String, dynamic>;
                final expenseId = exp['id']?.toString() ?? '';
                final title = exp['title']?.toString() ?? 'Despesa';
                final amount = exp['amount']?.toString() ?? '0';
                final status = exp['status']?.toString() ?? 'pending';
                final dueDate = exp['dueDate']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFormatter.format(
                                double.tryParse(amount) ?? 0,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (dueDate != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Vence: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(dueDate))}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'paid'
                              ? AppColors.status.success.withValues(alpha: 0.1)
                              : status == 'overdue'
                              ? AppColors.status.error.withValues(alpha: 0.1)
                              : AppColors.status.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status == 'paid'
                              ? 'Paga'
                              : status == 'overdue'
                              ? 'Vencida'
                              : 'Pendente',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status == 'paid'
                                ? AppColors.status.success
                                : status == 'overdue'
                                ? AppColors.status.error
                                : AppColors.status.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'mark_paid') {
                            _markExpenseAsPaid(context, property.id, expenseId);
                          } else if (value == 'edit') {
                            _showEditExpenseModal(context, property, expense);
                          } else if (value == 'delete') {
                            _deleteExpense(
                              context,
                              property.id,
                              expenseId,
                              title,
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          if (status != 'paid')
                            const PopupMenuItem(
                              value: 'mark_paid',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 18),
                                  SizedBox(width: 8),
                                  Text('Marcar como Paga'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Excluir',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              })),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist,
                        color: AppColors.primary.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Checklists',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    _showCreateChecklistModal(context, property);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Criar Checklist'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingChecklists)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_checklists.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.checklist_outlined,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum checklist cadastrado',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_checklists.take(5).map((checklist) {
                final chk = checklist as Map<String, dynamic>;
                final checklistId = chk['id']?.toString() ?? '';
                final type = chk['type']?.toString() ?? 'sale';
                final status = chk['status']?.toString() ?? 'pending';
                final stats = chk['statistics'] as Map<String, dynamic>?;
                final completionPercentage =
                    stats?['completionPercentage']?.toDouble() ?? 0.0;
                final client = chk['client'] as Map<String, dynamic>?;
                final clientName =
                    client?['name']?.toString() ?? 'Cliente não informado';

                return InkWell(
                  onTap: () {
                    // TODO: Navegar para detalhes do checklist quando a página existir
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Visualizar checklist: $checklistId'),
                        backgroundColor: AppColors.status.info,
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.background.backgroundSecondaryDarkMode
                          : AppColors.background.backgroundSecondary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Checklist de ${type == 'sale' ? 'Venda' : 'Aluguel'}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cliente: $clientName',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'completed'
                                    ? AppColors.status.success.withValues(
                                        alpha: 0.1,
                                      )
                                    : status == 'in_progress'
                                    ? AppColors.status.warning.withValues(
                                        alpha: 0.1,
                                      )
                                    : AppColors.background.backgroundSecondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status == 'completed'
                                    ? 'Concluído'
                                    : status == 'in_progress'
                                    ? 'Em Andamento'
                                    : 'Pendente',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: status == 'completed'
                                      ? AppColors.status.success
                                      : status == 'in_progress'
                                      ? AppColors.status.warning
                                      : ThemeHelpers.textSecondaryColor(
                                          context,
                                        ),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: completionPercentage / 100,
                                backgroundColor: ThemeHelpers.borderLightColor(
                                  context,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${completionPercentage.toStringAsFixed(0)}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              })),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.description,
                        color: AppColors.primary.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Documentos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.documentCreate).then((_) {
                      _loadDocuments();
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _isLoadingDocuments
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _documents.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 48,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum documento vinculado',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Adicione contratos, IPTU, matrícula e outros documentos relacionados a esta propriedade',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.documentCreate).then((_) {
                                _loadDocuments();
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar Documento'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      ..._documents.take(5).map((document) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors
                                      .background
                                      .backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ThemeHelpers.borderLightColor(context),
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.documentDetails(document.id),
                              );
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  color: AppColors.primary.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        document.title ?? document.originalName,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (document.description != null &&
                                          document.description!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          document.description!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    ThemeHelpers.textSecondaryColor(
                                                      context,
                                                    ),
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (_documents.length > 5) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.documents);
                          },
                          icon: const Icon(Icons.visibility),
                          label: Text('Ver Todos (${_documents.length})'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final address = property.address.isNotEmpty
        ? property.address
        : '${property.street}, ${property.number} - ${property.neighborhood}, ${property.city} - ${property.state}';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundSecondaryDarkMode
                  : AppColors.background.backgroundSecondary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 48,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mapa de Localização',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TODO: Integrar Google Maps ou OpenStreetMap',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 20,
                  color: AppColors.primary.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // TODO: Abrir no Google Maps ou aplicativo de mapas
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Abrir no mapa será implementado'),
                      ),
                    );
                  },
                  child: const Text('Abrir no Mapa'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(
    BuildContext context,
    ThemeData theme,
    List<String> features,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: features.map((feature) {
        return Chip(
          label: Text(feature),
          avatar: Icon(_getFeatureIcon(feature), size: 18),
        );
      }).toList(),
    );
  }

  IconData _getFeatureIcon(String feature) {
    // Mapeamento básico de ícones para recursos
    final iconMap = {
      'Ar condicionado': Icons.ac_unit,
      'Aquecimento': Icons.whatshot,
      'Elevador': Icons.elevator,
      'Portaria 24h': Icons.security,
      'Segurança 24h': Icons.shield,
      'Piscina': Icons.pool,
      'Academia': Icons.fitness_center,
      'Playground': Icons.child_care,
      'Churrasqueira': Icons.outdoor_grill,
      'Área gourmet': Icons.restaurant,
      'Jardim': Icons.local_florist,
      'Terraço': Icons.roofing,
      'Varanda': Icons.balcony,
      'Sacada': Icons.balcony,
      'Garagem coberta': Icons.garage,
      'Garagem descoberta': Icons.drive_eta,
      'Depósito': Icons.inventory_2,
      'Lavanderia': Icons.local_laundry_service,
      'Closet': Icons.checkroom,
      'Home office': Icons.work,
      'Lareira': Icons.fireplace,
      'Sistema de alarme': Icons.alarm,
      'Câmeras de segurança': Icons.videocam,
      'Internet': Icons.wifi,
      'Gás encanado': Icons.local_gas_station,
      'Água quente': Icons.water_drop,
      'Energia solar': Icons.solar_power,
      'Mobiliado': Icons.chair,
      'Semi-mobiliado': Icons.chair_outlined,
      'Pronto para morar': Icons.home,
      'Novo': Icons.new_releases,
    };

    return iconMap[feature] ?? Icons.check_circle_outline;
  }

  Color _getStatusColor(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.available:
        return AppColors.status.success;
      case PropertyStatus.sold:
        return AppColors.status.info;
      case PropertyStatus.rented:
        return AppColors.status.warning;
      case PropertyStatus.maintenance:
        return AppColors.status.warning;
      case PropertyStatus.draft:
        return AppColors.text.textSecondary;
    }
  }

  Future<void> _showLinkClientModal(
    BuildContext context,
    Property property,
  ) async {
    final selectedClientIdRef = <String?>[null];
    final selectedClientNameRef = <String?>[null];
    final selectedInterestTypeRef = <String?>[null];
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final interestTypes = ['buy', 'rent', 'both'];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vincular Cliente',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Client Selector
                  EntitySelector(
                    type: 'client',
                    selectedId: selectedClientIdRef[0],
                    selectedName: selectedClientNameRef[0],
                    onSelected: (id, name) {
                      setModalState(() {
                        selectedClientIdRef[0] = id;
                        selectedClientNameRef[0] = name;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Interest Type
                  Text(
                    'Tipo de Interesse *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: interestTypes.map((type) {
                      final labels = {
                        'buy': 'Compra',
                        'rent': 'Aluguel',
                        'both': 'Ambos',
                      };
                      final isSelected = selectedInterestTypeRef[0] == type;
                      return ChoiceChip(
                        label: Text(labels[type] ?? type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            selectedInterestTypeRef[0] = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Notes (optional)
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      hintText:
                          'Adicione observações sobre o interesse do cliente',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 24),
                  // Buttons (full width)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              if (selectedClientIdRef[0] == null ||
                                  selectedClientNameRef[0] == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Por favor, selecione um cliente',
                                    ),
                                    backgroundColor: AppColors.status.error,
                                  ),
                                );
                                return;
                              }
                              if (selectedInterestTypeRef[0] == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Por favor, selecione o tipo de interesse',
                                    ),
                                    backgroundColor: AppColors.status.error,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Vincular Cliente'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context, false);
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
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Usar try-finally para garantir que o controller seja sempre descartado
    try {
      if (result != true ||
          selectedClientIdRef[0] == null ||
          selectedInterestTypeRef[0] == null) {
        return;
      }

      // Capturar o texto antes de usar
      final notes = notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim();

      // Associar cliente à propriedade

      final response = await _clientService.associateClientToProperty(
        selectedClientIdRef[0]!,
        property.id,
        interestType: selectedInterestTypeRef[0]!,
        notes: notes,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente vinculado com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          // Recarregar propriedade para atualizar lista de clientes
          _loadProperty();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao vincular cliente'),
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
      // Sempre descartar o controller no final
      notesController.dispose();
    }
  }

  Future<void> _showCreateKeyModal(
    BuildContext context,
    Property property,
  ) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final keyTypeRef = <String>['main'];
    final keyTypes = [
      {'value': 'main', 'label': 'Principal'},
      {'value': 'backup', 'label': 'Reserva'},
      {'value': 'emergency', 'label': 'Emergência'},
      {'value': 'garage', 'label': 'Garagem'},
      {'value': 'mailbox', 'label': 'Caixa de Correio'},
      {'value': 'other', 'label': 'Outra'},
    ];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Criar Chave',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Chave *',
                      hintText: 'Ex: Chave Principal',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nome é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: keyTypes.map((type) {
                      final isSelected = keyTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            keyTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Localização',
                      hintText: 'Ex: Escritório',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Informações adicionais sobre a chave',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Chave'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true) {
        nameController.dispose();
        descriptionController.dispose();
        locationController.dispose();
        return;
      }

      final dto = key_models.CreateKeyDto(
        name: nameController.text.trim(),
        propertyId: property.id,
        type: keyTypeRef[0],
        status: 'available',
        location: locationController.text.trim().isNotEmpty
            ? locationController.text.trim()
            : null,
        description: descriptionController.text.trim().isNotEmpty
            ? descriptionController.text.trim()
            : null,
      );

      final response = await _keyService.createKey(dto);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave criada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadKeys();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar chave'),
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
      nameController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    }
  }

  Future<void> _showCreateExpenseModal(
    BuildContext context,
    Property property,
  ) async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final dueDateController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final expenseTypeRef = <String>['other'];
    final expenseTypes = [
      {'value': 'iptu', 'label': 'IPTU'},
      {'value': 'condominium', 'label': 'Condomínio'},
      {'value': 'insurance', 'label': 'Seguro'},
      {'value': 'maintenance', 'label': 'Manutenção'},
      {'value': 'utilities', 'label': 'Utilidades'},
      {'value': 'other', 'label': 'Outro'},
    ];

    DateTime? selectedDueDate;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Adicionar Despesa',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título *',
                      hintText: 'Ex: IPTU 2024',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Título é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: expenseTypes.map((type) {
                      final isSelected = expenseTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            expenseTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$) *',
                      hintText: '0,00',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Valor é obrigatório';
                      }
                      final amount = double.tryParse(
                        value.replaceAll(',', '.'),
                      );
                      if (amount == null || amount <= 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: dueDateController,
                    decoration: const InputDecoration(
                      labelText: 'Data de Vencimento *',
                      hintText: 'DD/MM/AAAA',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (date != null) {
                        setModalState(() {
                          selectedDueDate = date;
                          dueDateController.text = DateFormat(
                            'dd/MM/yyyy',
                          ).format(date);
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Data de vencimento é obrigatória';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Informações adicionais',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar Despesa'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true || selectedDueDate == null) {
        titleController.dispose();
        amountController.dispose();
        dueDateController.dispose();
        descriptionController.dispose();
        return;
      }

      final amount = double.parse(amountController.text.replaceAll(',', '.'));

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.propertyExpenses(property.id),
        body: {
          'title': titleController.text.trim(),
          'type': expenseTypeRef[0],
          'amount': amount,
          'dueDate': selectedDueDate!.toIso8601String(),
          'status': 'pending',
          if (descriptionController.text.trim().isNotEmpty)
            'description': descriptionController.text.trim(),
        },
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa adicionada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao adicionar despesa'),
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
      titleController.dispose();
      amountController.dispose();
      dueDateController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _showCreateChecklistModal(
    BuildContext context,
    Property property,
  ) async {
    final clientIdController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final checklistTypeRef = <String>['sale'];
    final checklistTypes = [
      {'value': 'sale', 'label': 'Venda'},
      {'value': 'rental', 'label': 'Aluguel'},
    ];

    final selectedClientIdRef = <String?>[null];
    final selectedClientNameRef = <String?>[null];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Criar Checklist',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: checklistTypes.map((type) {
                      final isSelected = checklistTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            checklistTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Cliente *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  EntitySelector(
                    type: 'client',
                    selectedId: selectedClientIdRef[0],
                    selectedName: selectedClientNameRef[0],
                    onSelected: (id, name) {
                      setModalState(() {
                        selectedClientIdRef[0] = id;
                        selectedClientNameRef[0] = name;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (selectedClientIdRef[0] == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Por favor, selecione um cliente',
                                  ),
                                  backgroundColor: AppColors.status.error,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Checklist'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true || selectedClientIdRef[0] == null) {
        clientIdController.dispose();
        return;
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.saleChecklists,
        body: {
          'propertyId': property.id,
          'clientId': selectedClientIdRef[0]!,
          'type': checklistTypeRef[0],
          'status': 'pending',
        },
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Checklist criado com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadChecklists();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar checklist'),
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
      clientIdController.dispose();
    }
  }

  Future<void> _markExpenseAsPaid(
    BuildContext context,
    String propertyId,
    String expenseId,
  ) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.propertyExpenseMarkAsPaid(propertyId, expenseId),
        body: {'paidDate': DateTime.now().toIso8601String()},
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa marcada como paga'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ?? 'Erro ao marcar despesa como paga',
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
    }
  }

  Future<void> _showEditExpenseModal(
    BuildContext context,
    Property property,
    Map<String, dynamic> expense,
  ) async {
    // Por enquanto, apenas mostra mensagem
    // TODO: Implementar modal de edição completo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Edição de despesa será implementada em breve'),
        backgroundColor: AppColors.status.info,
      ),
    );
  }

  Future<void> _deleteExpense(
    BuildContext context,
    String propertyId,
    String expenseId,
    String expenseTitle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.status.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Exclusão')),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir a despesa "$expenseTitle"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _apiService.delete<dynamic>(
        ApiConstants.propertyExpenseById(propertyId, expenseId),
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa excluída com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir despesa'),
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
    }
  }

  Future<void> _showEditKeyModal(
    BuildContext context,
    Property property,
    key_models.Key key,
  ) async {
    final nameController = TextEditingController(text: key.name);
    final descriptionController = TextEditingController(
      text: key.description ?? '',
    );
    final locationController = TextEditingController(text: key.location ?? '');
    final notesController = TextEditingController(text: key.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final keyTypeRef = <String>[key.type.value];
    final keyStatusRef = <String>[key.status.value];

    final keyTypes = [
      {'value': 'main', 'label': 'Principal'},
      {'value': 'backup', 'label': 'Reserva'},
      {'value': 'emergency', 'label': 'Emergência'},
      {'value': 'garage', 'label': 'Garagem'},
      {'value': 'mailbox', 'label': 'Caixa de Correio'},
      {'value': 'other', 'label': 'Outra'},
    ];

    final keyStatuses = [
      {'value': 'available', 'label': 'Disponível'},
      {'value': 'in_use', 'label': 'Em Uso'},
      {'value': 'lost', 'label': 'Perdida'},
      {'value': 'damaged', 'label': 'Danificada'},
      {'value': 'maintenance', 'label': 'Manutenção'},
    ];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Editar Chave',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Chave *',
                      hintText: 'Ex: Chave Principal',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nome é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: keyTypes.map((type) {
                      final isSelected = keyTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            keyTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Status *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: keyStatuses.map((status) {
                      final isSelected = keyStatusRef[0] == status['value'];
                      return ChoiceChip(
                        label: Text(status['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            keyStatusRef[0] = status['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Localização',
                      hintText: 'Ex: Escritório',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Informações adicionais sobre a chave',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      hintText: 'Notas adicionais',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Salvar Alterações'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true) {
        nameController.dispose();
        descriptionController.dispose();
        locationController.dispose();
        notesController.dispose();
        return;
      }

      final dto = key_models.UpdateKeyDto(
        name: nameController.text.trim(),
        description: descriptionController.text.trim().isNotEmpty
            ? descriptionController.text.trim()
            : null,
        type: keyTypeRef[0],
        status: keyStatusRef[0],
        location: locationController.text.trim().isNotEmpty
            ? locationController.text.trim()
            : null,
        notes: notesController.text.trim().isNotEmpty
            ? notesController.text.trim()
            : null,
      );

      final response = await _keyService.updateKey(key.id, dto);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave atualizada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadKeys();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar chave'),
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
      nameController.dispose();
      descriptionController.dispose();
      locationController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _deleteKey(
    BuildContext context,
    String propertyId,
    String keyId,
    String keyName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.status.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Exclusão')),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir a chave "$keyName"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _keyService.deleteKey(keyId);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave excluída com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadKeys();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir chave'),
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
    }
  }
}
