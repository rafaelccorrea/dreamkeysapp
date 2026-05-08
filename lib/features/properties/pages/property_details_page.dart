import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../shared/services/gallery_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../core/constants/app_permissions.dart';
import '../utils/property_edit_permissions.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Aba interna da ficha de imóvel.
enum _DetailsTab { overview, commercial, management }

extension on _DetailsTab {
  String get label {
    switch (this) {
      case _DetailsTab.overview:
        return 'Visão geral';
      case _DetailsTab.commercial:
        return 'Comercial';
      case _DetailsTab.management:
        return 'Gestão';
    }
  }

  IconData get icon {
    switch (this) {
      case _DetailsTab.overview:
        return Icons.storefront_outlined;
      case _DetailsTab.commercial:
        return Icons.handshake_outlined;
      case _DetailsTab.management:
        return Icons.fact_check_outlined;
    }
  }
}

/// Página de detalhes da propriedade
class PropertyDetailsPage extends StatefulWidget {
  final String propertyId;
  final Property? initialProperty;

  const PropertyDetailsPage({
    super.key,
    required this.propertyId,
    this.initialProperty,
  });

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

  /// Aba interna ativa: Visão geral, Comercial ou Gestão.
  _DetailsTab _activeTab = _DetailsTab.overview;

  /// Controlador da rolagem — controla FAB "voltar ao topo".
  final ScrollController _detailsScrollController = ScrollController();
  bool _showScrollTopFab = false;
  String? _lastImageDiagnosticsSignature;

  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  List<dynamic> _extractChecklists(dynamic payload) {
    if (payload is List) return payload;
    final rootMap = _asStringKeyedMap(payload);
    if (rootMap == null) return const [];

    final directCandidates = [
      rootMap['checklists'],
      rootMap['data'],
      rootMap['items'],
      rootMap['results'],
    ];
    for (final candidate in directCandidates) {
      if (candidate is List) return candidate;
    }

    final nestedData = _asStringKeyedMap(rootMap['data']);
    if (nestedData != null) {
      final nestedCandidates = [
        nestedData['checklists'],
        nestedData['data'],
        nestedData['items'],
        nestedData['results'],
      ];
      for (final candidate in nestedCandidates) {
        if (candidate is List) return candidate;
      }
    }

    return const [];
  }

  double _extractChecklistCompletionPercentage(Map<String, dynamic> checklist) {
    final stats =
        _asStringKeyedMap(checklist['statistics']) ??
        _asStringKeyedMap(checklist['stats']) ??
        _asStringKeyedMap(checklist['metrics']);

    final directPercentage =
        _asDouble(stats?['completionPercentage']) ??
        _asDouble(stats?['completion_percentage']) ??
        _asDouble(stats?['progressPercentage']) ??
        _asDouble(stats?['progress_percentage']) ??
        _asDouble(stats?['completion']) ??
        _asDouble(checklist['completionPercentage']) ??
        _asDouble(checklist['completion_percentage']);

    if (directPercentage != null) {
      return directPercentage.clamp(0, 100).toDouble();
    }

    final totalTasks =
        _asDouble(stats?['totalTasks']) ??
        _asDouble(stats?['total_tasks']) ??
        _asDouble(stats?['total']) ??
        _asDouble(checklist['totalTasks']) ??
        _asDouble(checklist['total_tasks']);
    final completedTasks =
        _asDouble(stats?['completedTasks']) ??
        _asDouble(stats?['completed_tasks']) ??
        _asDouble(stats?['doneTasks']) ??
        _asDouble(stats?['done_tasks']) ??
        _asDouble(stats?['completed']) ??
        _asDouble(checklist['completedTasks']) ??
        _asDouble(checklist['completed_tasks']) ??
        _asDouble(checklist['doneTasks']) ??
        _asDouble(checklist['done_tasks']);

    if (totalTasks != null && totalTasks > 0 && completedTasks != null) {
      return ((completedTasks / totalTasks) * 100).clamp(0, 100).toDouble();
    }

    return 0;
  }

  /// Avaliação alinhada às regras do backend (master/admin/manager, aprovador
  /// na matriz, vínculo como responsável/captador, ou autorização de venda
  /// assinada bloqueando vinculados). Veja
  /// `property_edit_permissions.dart` para a lógica completa.
  PropertyEditPermissionResult get _editPermission {
    final access = ModuleAccessService.instance;
    return evaluatePropertyEditPermission(
      property: _property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
  }

  bool get _canEditProperty => _editPermission.canEdit;

  bool get _canDeleteProperty {
    final access = ModuleAccessService.instance;
    return canUserDeleteThisPropertyRecord(
      property: _property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
  }

  /// Pode deletar imagens individuais do imóvel direto pelo carrossel
  /// fullscreen (paridade com `imobx-front/PropertyGalleryFullscreenPage`).
  ///
  /// Espelha exatamente a regra do web:
  ///   `master/admin OR property:approve_publication OR property:approve_availability`
  ///
  /// Backend: `DELETE /gallery/:id` valida ownership pela company; o front
  /// é quem decide se o botão aparece. Útil pra reprovar fotos individuais
  /// (não-quadradas, categoria errada) sem precisar mandar a publicação
  /// inteira de volta pra fila.
  bool get _canDeletePropertyImages {
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase() ?? '';
    if (role == 'master' || role == 'admin') return true;
    return access.hasPermission(AppPermissions.propertyApprovePublication) ||
        access.hasPermission(AppPermissions.propertyApproveAvailability);
  }

  @override
  void initState() {
    super.initState();
    _property = widget.initialProperty;
    // Sempre inicia em loading para evitar "tela vazia" com `initialProperty`
    // parcial e garantir feedback visual consistente.
    _isLoading = true;
    _loadProperty();
    _detailsScrollController.addListener(_handleDetailsScroll);
  }

  void _handleDetailsScroll() {
    if (!_detailsScrollController.hasClients) return;
    final offset = _detailsScrollController.offset;
    final shouldShow = offset > 480;
    if (shouldShow != _showScrollTopFab) {
      setState(() => _showScrollTopFab = shouldShow);
    }
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
            _checklists = _extractChecklists(response.data);
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
    _detailsScrollController
      ..removeListener(_handleDetailsScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadProperty() async {
    if (widget.propertyId.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'ID do imóvel inválido.';
      });
      return;
    }

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
          final property = response.data!;
          if (property.id.trim().isEmpty) {
            setState(() {
              _errorMessage = 'Imóvel retornou sem identificador válido.';
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _property = property;
            _isLoading = false;
          });
          _debugLogPropertyImageDiagnostics(
            property,
            source: 'loadProperty.success',
          );
          // Carregar dados relacionados após carregar propriedade
          _loadDocuments();
          _loadChecklists();
          _loadExpenses();
          _loadKeys();
        } else {
          setState(() {
            // Se já existe algum snapshot local da propriedade, mantém a tela
            // renderizada em vez de trocar para estado de erro cheio.
            if (_property == null) {
              _errorMessage =
                  response.message ?? 'Erro ao carregar propriedade';
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_DETAILS] Erro: $e');
      if (mounted) {
        setState(() {
          if (_property == null) {
            _errorMessage = 'Erro ao conectar com o servidor';
          }
          _isLoading = false;
        });
      }
    }
  }

  void _debugLogPropertyImageDiagnostics(
    Property property, {
    required String source,
  }) {
    if (!kDebugMode) return;
    final allImages = property.images ?? const <PropertyImage>[];
    final validImages =
        allImages.where((img) => img.url.trim().isNotEmpty).toList();
    final mainUrl = property.mainImage?.url.trim() ?? '';
    final signature =
        '${property.id}|${allImages.length}|${validImages.length}|$mainUrl|'
        '${allImages.take(3).map((e) => e.url).join('|')}';
    if (_lastImageDiagnosticsSignature == signature) return;
    _lastImageDiagnosticsSignature = signature;

    debugPrint('🖼️ [PROPERTY_DETAILS] Diagnóstico de imagens ($source)');
    debugPrint('   - propertyId: ${property.id}');
    debugPrint('   - imageCount(api): ${property.imageCount}');
    debugPrint('   - images.length(raw): ${allImages.length}');
    debugPrint('   - images.length(valid): ${validImages.length}');
    debugPrint(
      '   - mainImage.id/url: ${property.mainImage?.id ?? '-'} / '
      '${mainUrl.isEmpty ? '(vazio)' : mainUrl}',
    );
    if (allImages.isEmpty) {
      debugPrint('   - image list veio vazia');
      return;
    }
    for (var i = 0; i < allImages.length && i < 5; i++) {
      final img = allImages[i];
      debugPrint(
        '   - image[$i] id=${img.id} | isMain=${img.isMain} | url="${img.url}"',
      );
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
        Builder(
          builder: (context) {
            // Esconde o menu por completo se o usuário não tem nenhuma ação
            // disponível (visualização-pura para imóvel de outro corretor).
            final canEdit = _canEditProperty;
            final canDelete = _canDeleteProperty;
            final hasOffersShortcut =
                _property != null && _property!.hasPendingOffers == true;
            if (!canEdit && !canDelete && !hasOffersShortcut) {
              return const SizedBox.shrink();
            }
            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    if (!canEdit) return;
                    Navigator.of(
                      context,
                    ).pushNamed('/properties/${widget.propertyId}/edit');
                    break;
                  case 'delete':
                    if (!canDelete) return;
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
                if (canEdit)
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
                if (hasOffersShortcut)
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
                if (canDelete)
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
            );
          },
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : () {
              final property = _property;
              if (property == null) {
                return _buildErrorState(
                  context,
                  theme,
                  message: 'Não foi possível carregar os detalhes do imóvel.',
                );
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: _buildPropertyDetails(context, theme, property),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomActionBar(context, theme, property),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    right: 16,
                    bottom: _showScrollTopFab ? 92 : -64,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _showScrollTopFab ? 1 : 0,
                      child: _buildScrollTopButton(context, theme),
                    ),
                  ),
                ],
              );
            }(),
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

  Widget _buildErrorState(
    BuildContext context,
    ThemeData theme, {
    String? message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              message ?? _errorMessage ?? 'Erro ao carregar propriedade',
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
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;

    // Layout reformulado em estilo editorial:
    //
    // 1. Hero edge-to-edge (sem bordas arredondadas, sem padding lateral)
    //    — a foto é o protagonista e ocupa toda a largura da tela.
    // 2. Bloco "headline" (tipo + código + título + endereço) sem caixa.
    // 3. Quick stats em strip horizontal.
    // 4. Preço em destaque tipográfico (sem caixa).
    // 5. Ações rápidas.
    // 6. Tabs + conteúdo da aba.
    //
    // Essa ordem coloca a informação mais importante (foto → título →
    // preço) com hierarquia visual real, em vez de "card dentro de card
    // dentro de card" que era o layout antigo.
    return CustomScrollView(
      controller: _detailsScrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // 1. HERO sem padding lateral, edge-to-edge
        SliverToBoxAdapter(
          child: _buildDetailsHero(context, theme, property),
        ),
        // 2. IDENTIDADE — sem caixa, só tipografia
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _buildIdentityCard(context, theme, property, muted, isDark),
          ),
        ),
        // 3. STATS strip
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _buildQuickStatsStrip(context, theme, property),
          ),
        ),
        // Divisor sutil antes do preço — separa "identidade" de "valor"
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.55),
            ),
          ),
        ),
        // 4. PREÇO em destaque tipográfico
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _buildPriceShowcase(context, theme, property, isDark),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _buildQuickActionsStrip(context, theme, property),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _buildSectionTabs(context, theme),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            child: _buildActiveTabContent(context, theme, property),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────── HERO ──────────────────────────────

  /// Hero **edge-to-edge** — a foto é o protagonista da tela.
  ///
  /// Mudanças em relação à versão anterior:
  /// - Sem `borderRadius: 20` — bordas retas, full-width
  /// - Sem `Material elevation` + sombra — fica visualmente "preso" ao topo
  /// - Sem `padding lateral 16` — ocupa 100% da largura da tela
  /// - Altura de **340px** (era 248) pra dar mais peso visual à foto
  /// - **Título do imóvel + endereço sobrepostos** no rodapé da imagem
  ///   (estilo Airbnb/Booking) com gradiente bottom mais forte
  /// - Featured/contador/dots reposicionados pra não brigar com o título
  Widget _buildDetailsHero(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final rawImages = property.images ?? const <PropertyImage>[];
    final validImages =
        rawImages.where((img) => img.url.trim().isNotEmpty).toList();
    final hasValidMainImage =
        property.mainImage?.url.trim().isNotEmpty == true;
    // Alguns payloads chegam com `mainImage` válida e `images` vazia.
    final images = validImages.isNotEmpty
        ? validImages
        : (hasValidMainImage
            ? <PropertyImage>[property.mainImage!]
            : const <PropertyImage>[]);
    final safeCurrentIndex = images.isEmpty
        ? 0
        : _currentImageIndex.clamp(0, images.length - 1);
    if (kDebugMode && rawImages.length != validImages.length) {
      debugPrint(
        '⚠️ [PROPERTY_DETAILS] Imagens com URL inválida/vazia: '
        '${rawImages.length - validImages.length} de ${rawImages.length}',
      );
    }
    if (kDebugMode && images.isEmpty) {
      debugPrint(
        '⚠️ [PROPERTY_DETAILS] Hero sem imagem renderizável. '
        'mainImage="${property.mainImage?.url ?? '(null)'}" '
        'imagesRaw=${rawImages.length}',
      );
    }
    final mediaCount = property.imageCount ?? images.length;
    const heroH = 340.0;
    final isDark = theme.brightness == Brightness.dark;

    Widget imageLayer() => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: images.isEmpty
              ? null
              : () => _openFullscreenGallery(images, safeCurrentIndex),
          child: images.isEmpty
              ? _buildHeroFallback(context, theme)
              : PageView.builder(
                  controller: _imagePageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImageIndex = i),
                  itemBuilder: (_, i) => Hero(
                    tag: 'property-image-${property.id}-$i',
                    child: ShimmerImage(
                      imageUrl: images[i].url,
                      width: double.infinity,
                      height: heroH,
                      fit: BoxFit.cover,
                      errorWidget: _buildHeroFallback(context, theme),
                    ),
                  ),
                ),
        );

    return SizedBox(
      width: double.infinity,
      height: heroH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: imageLayer()),

          // Gradient bottom mais forte — necessário pro título sobreposto
          // ler bem em fotos claras. Top também tem um leve "veneer" pra
          // contadores/featured chip.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.32, 0.6, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.5 : 0.38),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),

          if (property.isFeatured)
            Positioned(
              top: 16,
              right: 16,
              child: _buildHeroFeaturedChip(),
            ),
          if (mediaCount > 1)
            Positioned(
              right: 16,
              top: 16,
              child: _buildHeroMediaCounter(
                images.isEmpty ? 1 : safeCurrentIndex + 1,
                mediaCount,
              ),
            ),
          if (images.isNotEmpty)
            Positioned(
              left: 16,
              top: 16,
              child: _buildExpandHint(),
            ),

          // Setas laterais para navegação entre fotos
          if (images.length > 1 && safeCurrentIndex > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildHeroNavArrow(
                  Icons.chevron_left_rounded,
                  () => _imagePageController.previousPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
          if (images.length > 1 && safeCurrentIndex < images.length - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildHeroNavArrow(
                  Icons.chevron_right_rounded,
                  () => _imagePageController.nextPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),

          // Título + endereço sobrepostos no rodapé
          Positioned(
            left: 20,
            right: 20,
            bottom: images.length > 1 ? 28 : 20,
            child: _buildHeroOverlay(theme, property),
          ),

          // Dots no fim (apenas quando há mais de uma imagem)
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: _buildHeroDots(images.length, safeCurrentIndex),
              ),
            ),
        ],
      ),
    );
  }

  /// Overlay de título no rodapé da hero — substitui o que era "linha de
  /// chips de tipo + título grande" do antigo `_buildIdentityCard` (que
  /// vinha em CIMA de outro container abaixo da foto).
  ///
  /// Branco-sobre-foto-com-gradiente é o padrão de Airbnb/Booking pra
  /// "fichas" de imóvel — a foto é a protagonista, o nome dela aparece
  /// como manchete sobreposta.
  Widget _buildHeroOverlay(ThemeData theme, Property property) {
    final fullAddress = property.neighborhood.isNotEmpty
        ? '${property.neighborhood} · ${property.city}/${property.state}'
        : '${property.city}/${property.state}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tipo do imóvel como eyebrow accent claro
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _typeIcon(property.type),
                size: 11,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                property.type.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          property.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.1,
            color: Colors.white,
            shadows: [
              Shadow(
                offset: const Offset(0, 1),
                blurRadius: 4,
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.place_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                fullAddress,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.zoom_out_map_rounded, size: 12, color: Colors.white),
          SizedBox(width: 5),
          Text(
            'Toque para ampliar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }

  void _openFullscreenGallery(List<PropertyImage> images, int initial) {
    Navigator.of(context)
        .push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullscreenGallery(
          images: images,
          initialIndex: initial,
          propertyId: _property?.id ?? '',
          canDelete: _canDeletePropertyImages,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    )
        .then((didMutate) {
      // Quando o user deleta uma ou mais fotos pelo fullscreen, recarregamos
      // o property pra refletir nova `mainImage`/`images` (e contadores).
      if (didMutate == true && mounted) {
        _loadProperty();
      }
    });
  }

  Widget _buildHeroFallback(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.background.backgroundDarkMode,
                  AppColors.background.backgroundSecondaryDarkMode,
                ]
              : [
                  AppColors.background.backgroundSecondary,
                  AppColors.background.background,
                ],
        ),
      ),
      child: Center(
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: AppColors.primary.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.home_work_outlined,
            size: 44,
            color: AppColors.primary.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroFeaturedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), Color(0xFFFFA000)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.85),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFA000).withValues(alpha: 0.42),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.star_rounded, size: 14, color: Color(0xFF4E342E)),
          SizedBox(width: 5),
          Text(
            'Em destaque',
            style: TextStyle(
              color: Color(0xFF3E2723),
              fontWeight: FontWeight.w900,
              fontSize: 11,
              height: 1,
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMediaCounter(int current, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '$current / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Indicadores de página da hero.
  ///
  /// Antes usava um `Row` com `total` dots — quebrava em overflow quando
  /// o imóvel tinha 12+ fotos (ex.: 20 dots × ~12px = 240px+ que estoura
  /// telas estreitas). Agora aplicamos uma regra adaptativa:
  ///
  /// - Até **8 fotos**: mostra dots tradicionais (Instagram-like).
  /// - Mais que isso: usa um **indicador compacto "X / Y"** com fundo
  ///   semitransparente — escala bem para qualquer número de fotos.
  Widget _buildHeroDots(int total, int current) {
    if (total > 8) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${current + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: '  /  $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildHeroNavArrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  // ────────────────────────────── IDENTIDADE ──────────────────────────────

  /// Bloco de "identidade" reformulado — **sem caixa visual encapsulada**.
  ///
  /// Antes era um DecoratedBox com borderRadius 20, sombra e ClipRRect
  /// envolvendo tudo, criando um "card sobre card". Repetia também o
  /// título + tipo + endereço que agora estão sobrepostos na hero.
  ///
  /// Agora é só conteúdo direto sobre o background da página:
  /// - Linha de código + matches badge + relacionados (compacto)
  /// - Pills de meta-status (público/privado, aceita proposta, MCMV…)
  /// - Footer de identidade (se houver) — separado por linha sutil
  Widget _buildIdentityCard(
    BuildContext context,
    ThemeData theme,
    Property property,
    Color muted,
    bool isDark,
  ) {
    final pills = _buildIdentityMetaPills(property, isDark);
    final hasFooter = _hasIdentityFooterContent(property);
    final hasCode = property.code != null && property.code!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Linha código + matches — informação meta, em peso secundário
        Row(
          children: [
            if (hasCode) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: property.code!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: muted.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tag, size: 12, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        property.code!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: muted,
                          letterSpacing: 0.3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            // Matches badge — vai pra direita pra ficar visualmente equilibrado
            Expanded(
              child: Align(
                alignment: hasCode
                    ? Alignment.centerLeft
                    : Alignment.centerLeft,
                child: MatchesBadge(
                  propertyId: widget.propertyId,
                  onClick: () => Navigator.pushNamed(
                    context,
                    AppRoutes.matchesByProperty(widget.propertyId),
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),

        // Pills de meta-status (público, MCMV, aceita proposta, etc)
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pills,
          ),
        ],

        // Footer extra (responsável, captador, etc) — quando existe,
        // separado por linha fina pra dividir hierarquia
        if (hasFooter) ...[
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context)
                .withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          _buildIdentityFooter(theme, property, muted),
        ],
      ],
    );
  }

  /// Pills com meta-info do imóvel: público, MCMV, aceita proposta, ofertas.
  List<Widget> _buildIdentityMetaPills(Property property, bool isDark) {
    final pills = <Widget>[];

    final publicLive =
        property.isAvailableForSite == true && property.isActive;
    pills.add(_metaPill(
      icon: publicLive ? Icons.public : Icons.lock_outline_rounded,
      label: publicLive ? 'No site' : 'Privado',
      color: publicLive ? AppColors.status.success : AppColors.text.textSecondary,
      isDark: isDark,
    ));

    if (property.acceptsNegotiation == true) {
      pills.add(_metaPill(
        icon: Icons.handshake_outlined,
        label: 'Aceita proposta',
        color: AppColors.status.success,
        isDark: isDark,
      ));
    }
    if (property.mcmvEligible == true) {
      pills.add(_metaPill(
        icon: Icons.home_work_outlined,
        label: 'MCMV',
        color: AppColors.status.info,
        isDark: isDark,
      ));
    }
    final pending = property.pendingOffersCount ?? 0;
    if (pending > 0) {
      pills.add(_metaPill(
        icon: Icons.request_quote_outlined,
        label: '$pending oferta${pending > 1 ? 's' : ''} pendente${pending > 1 ? 's' : ''}',
        color: AppColors.status.warning,
        isDark: isDark,
      ));
    }
    if ((property.imageCount ?? property.images?.length ?? 0) == 0) {
      pills.add(_metaPill(
        icon: Icons.image_not_supported_outlined,
        label: 'Sem fotos',
        color: AppColors.status.warning,
        isDark: isDark,
      ));
    }
    return pills;
  }

  Widget _metaPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasIdentityFooterContent(Property property) {
    return property.updatedAt.isNotEmpty ||
        property.capturedBy != null ||
        property.createdAt.isNotEmpty;
  }

  Widget _buildIdentityFooter(ThemeData theme, Property property, Color muted) {
    final updatedAgo = _humanRelativeTime(property.updatedAt);
    final captured = property.capturedBy?.name;
    final createdAgo = _humanRelativeTime(property.createdAt);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        if (updatedAgo != null)
          _identityMicroInfo(
            icon: Icons.history_rounded,
            label: 'Atualizado $updatedAgo',
            muted: muted,
            theme: theme,
          ),
        if (captured != null && captured.isNotEmpty)
          _identityMicroInfo(
            icon: Icons.person_pin_circle_outlined,
            label: 'Captado por $captured',
            muted: muted,
            theme: theme,
          ),
        if (updatedAgo == null && createdAgo != null)
          _identityMicroInfo(
            icon: Icons.event_available_outlined,
            label: 'Criado $createdAgo',
            muted: muted,
            theme: theme,
          ),
      ],
    );
  }

  Widget _identityMicroInfo({
    required IconData icon,
    required String label,
    required Color muted,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  /// Devolve algo como "há 3d", "há 2h" ou null se a string for inválida.
  String? _humanRelativeTime(String iso) {
    if (iso.trim().isEmpty) return null;
    DateTime? dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
    final delta = DateTime.now().difference(dt);
    if (delta.isNegative) return null;
    if (delta.inMinutes < 1) return 'agora';
    if (delta.inMinutes < 60) return 'há ${delta.inMinutes} min';
    if (delta.inHours < 24) return 'há ${delta.inHours} h';
    if (delta.inDays < 7) return 'há ${delta.inDays} d';
    if (delta.inDays < 30) return 'há ${(delta.inDays / 7).floor()} sem';
    if (delta.inDays < 365) return 'há ${(delta.inDays / 30).floor()} mes';
    return 'há ${(delta.inDays / 365).floor()} a';
  }

  IconData _typeIcon(PropertyType type) {
    switch (type) {
      case PropertyType.house:
        return Icons.cottage_outlined;
      case PropertyType.apartment:
        return Icons.apartment;
      case PropertyType.commercial:
        return Icons.storefront_outlined;
      case PropertyType.land:
        return Icons.terrain_outlined;
      case PropertyType.rural:
        return Icons.agriculture_outlined;
    }
  }

  // ────────────────────────────── QUICK STATS ──────────────────────────────

  Widget _buildQuickStatsStrip(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final stats = <({IconData icon, String value, String label})>[];
    if (property.bedrooms != null && property.bedrooms! > 0) {
      stats.add((icon: Icons.king_bed_outlined, value: '${property.bedrooms}', label: 'Quartos'));
    }
    if (property.bathrooms != null && property.bathrooms! > 0) {
      stats.add((icon: Icons.bathtub_outlined, value: '${property.bathrooms}', label: 'Banheiros'));
    }
    if (property.parkingSpaces != null && property.parkingSpaces! > 0) {
      stats.add((
        icon: Icons.directions_car_filled_outlined,
        value: '${property.parkingSpaces}',
        label: 'Vagas',
      ));
    }
    if (property.totalArea > 0) {
      stats.add((
        icon: Icons.square_foot_rounded,
        value: '${property.totalArea.toInt()}',
        label: 'm² total',
      ));
    }
    if (property.builtArea != null && property.builtArea! > 0) {
      stats.add((
        icon: Icons.crop_free_rounded,
        value: '${property.builtArea!.toInt()}',
        label: 'm² const.',
      ));
    }
    if (stats.isEmpty) return const SizedBox.shrink();

    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final accent = isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: ColoredBox(
          color: cardBg,
          child: SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              itemCount: stats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = stats[i];
                return Container(
                  width: 88,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  decoration: BoxDecoration(
                    color: (isDark
                            ? AppColors.background.backgroundSecondaryDarkMode
                            : AppColors.background.backgroundSecondary)
                        .withValues(alpha: isDark ? 0.72 : 0.88),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor.withValues(alpha: isDark ? 0.5 : 0.65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(s.icon, size: 13, color: accent),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -0.35,
                          color: ThemeHelpers.textColor(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontSize: 9,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────── PRICE SHOWCASE ──────────────────────────────

  Widget _buildPriceShowcase(
    BuildContext context,
    ThemeData theme,
    Property property,
    bool isDark,
  ) {
    final hasSale = property.salePrice != null;
    final hasRent = property.rentPrice != null;
    if (!hasSale && !hasRent) {
      return _buildPriceUnavailableCard(context, theme, isDark);
    }

    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    // Bloco de preço editorial — **sem caixa**.
    //
    // O preço é a informação mais importante depois da foto: ele é a
    // razão de o imóvel existir na vitrine. Antes ficava encapsulado
    // numa caixa secundária, sem destaque tipográfico real.
    //
    // Agora é só um padding inline sobre o background da página, com a
    // hierarquia tipográfica fazendo o trabalho: eyebrow accent fino +
    // valor grande em peso 900 + chips de meta abaixo.
    return hasSale && hasRent
        ? _buildPriceDualLayout(theme, property, accent, isDark)
        : _buildPriceSingleLayout(theme, property, hasSale, accent, isDark);
  }

  Widget _buildPriceUnavailableCard(BuildContext context, ThemeData theme, bool isDark) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.cardBackgroundDarkMode
            : AppColors.background.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (isDark
                  ? AppColors.border.borderDarkMode
                  : AppColors.border.border)
              .withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.price_change_outlined, size: 22, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preço sob consulta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Preencha os valores na ficha para apresentar nesta tela.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSingleLayout(
    ThemeData theme,
    Property property,
    bool isSale,
    Color accent,
    bool isDark,
  ) {
    final value = isSale ? property.salePrice! : property.rentPrice!;
    final label = isSale ? 'VENDA' : 'LOCAÇÃO';
    final icon = isSale ? Icons.sell_outlined : Icons.vpn_key_outlined;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPriceLabelRow(label, icon, accent),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'R\$',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _currencyFormatter
                      .format(value)
                      .replaceAll('R\$', '')
                      .trim(),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    fontSize: 38,
                    height: 1.05,
                    letterSpacing: -1.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (!isSale)
              Padding(
                padding: const EdgeInsets.only(top: 14, left: 4),
                child: Text(
                  '/mês',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
          ],
        ),
        if (property.acceptsNegotiation == true) ...[
          const SizedBox(height: 12),
          _buildAcceptsNegotiationChip(theme, isDark),
        ],
      ],
    );
  }

  Widget _buildPriceDualLayout(
    ThemeData theme,
    Property property,
    Color accent,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPriceLabelRow('VENDA · LOCAÇÃO', Icons.compare_arrows_rounded, accent),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPriceColumn(
                theme,
                'Venda',
                _currencyFormatter
                    .format(property.salePrice)
                    .replaceAll('R\$', '')
                    .trim(),
                Icons.sell_outlined,
                accent,
              ),
            ),
            Container(
              width: 1,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
            Expanded(
              child: _buildPriceColumn(
                theme,
                'Aluguel/mês',
                _currencyFormatter
                    .format(property.rentPrice)
                    .replaceAll('R\$', '')
                    .trim(),
                Icons.vpn_key_outlined,
                accent,
              ),
            ),
          ],
        ),
        if (property.acceptsNegotiation == true) ...[
          const SizedBox(height: 12),
          _buildAcceptsNegotiationChip(theme, isDark),
        ],
      ],
    );
  }

  Widget _buildPriceColumn(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color accent,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: muted),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'R\$',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    letterSpacing: -0.6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceLabelRow(String label, IconData icon, Color accent) {
    return Row(
      children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptsNegotiationChip(ThemeData theme, bool isDark) {
    final c = AppColors.status.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: isDark ? 0.18 : 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.handshake_outlined, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            'Aceita proposta',
            style: theme.textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────── QUICK ACTIONS ──────────────────────────────

  Widget _buildQuickActionsStrip(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final actions = <({IconData icon, String label, VoidCallback onTap, Color? color})>[
      (
        icon: Icons.location_on_outlined,
        label: 'Mapa',
        onTap: () => _scrollToBottom(context),
        color: null,
      ),
      (
        icon: Icons.share_outlined,
        label: 'Compartilhar',
        onTap: () {
          final url = property.code != null && property.code!.isNotEmpty
              ? 'imovel/${property.code}'
              : 'imovel/${property.id}';
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link copiado'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        color: null,
      ),
      if (property.totalOffersCount != null && property.totalOffersCount! > 0)
        (
          icon: Icons.request_quote_outlined,
          label: 'Ofertas',
          onTap: () => Navigator.of(context).pushNamed(
            '/properties/offers',
            arguments: {'propertyId': widget.propertyId},
          ),
          color: AppColors.status.warning,
        ),
      // Botão "Editar" só aparece se o usuário tem direito de alterar a ficha
      // (gestão, aprovador ou vínculo). Espelha exatamente o backend.
      if (_canEditProperty)
        (
          icon: Icons.edit_outlined,
          label: 'Editar',
          onTap: () => Navigator.of(context).pushNamed(
            '/properties/${widget.propertyId}/edit',
          ),
          color: null,
        ),
    ];

    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = actions[i];
          final c = a.color ?? accent;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: a.onTap,
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: 0.28)),
                ),
                child: Row(
                  children: [
                    Icon(a.icon, size: 16, color: c),
                    const SizedBox(width: 7),
                    Text(
                      a.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: a.color != null ? c : muted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _scrollToBottom(BuildContext context) {
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  // ────────────────────────────── TABS ──────────────────────────────

  Widget _buildSectionTabs(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor.withValues(alpha: isDark ? 0.55 : 0.7)),
        ),
        child: Row(
          children: _DetailsTab.values.map((tab) {
            final active = tab == _activeTab;
            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _activeTab = tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? accent : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tab.icon,
                          size: 16,
                          color: active ? Colors.white : muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: active ? Colors.white : muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    switch (_activeTab) {
      case _DetailsTab.overview:
        return _buildOverviewTab(context, theme, property);
      case _DetailsTab.commercial:
        return _buildCommercialTab(context, theme, property);
      case _DetailsTab.management:
        return _buildManagementTab(context, theme, property);
    }
  }

  Widget _buildOverviewTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Descrição', Icons.notes_outlined),
        const SizedBox(height: 10),
        _buildDescriptionCard(context, theme, property),
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Características', Icons.tune_rounded),
        const SizedBox(height: 10),
        _buildCharacteristicsCard(context, theme, property),
        if (property.condominiumFee != null || property.iptu != null) ...[
          const SizedBox(height: 22),
          _buildSectionHeader(theme, 'Valores adicionais', Icons.account_balance_wallet_outlined),
          const SizedBox(height: 10),
          _buildAdditionalValuesCard(context, theme, property),
        ],
        if (property.features.isNotEmpty) ...[
          const SizedBox(height: 22),
          _buildSectionHeader(theme, 'Recursos e comodidades', Icons.auto_awesome_outlined),
          const SizedBox(height: 10),
          _buildFeaturesSection(context, theme, property.features),
        ],
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Localização', Icons.map_outlined),
        const SizedBox(height: 10),
        _buildMapSection(context, theme, property),
      ],
    );
  }

  Widget _buildCommercialTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final hasOffers = property.hasPendingOffers == true ||
        (property.totalOffersCount != null && property.totalOffersCount! > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Status da chave', Icons.vpn_key_outlined),
        const SizedBox(height: 10),
        _buildKeyStatusSection(context, theme, property),
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Clientes vinculados', Icons.people_alt_outlined),
        const SizedBox(height: 10),
        _buildClientsSection(context, theme, property),
        if (hasOffers) ...[
          const SizedBox(height: 22),
          _buildSectionHeader(theme, 'Ofertas', Icons.request_quote_outlined),
          const SizedBox(height: 10),
          _buildOffersSection(context, theme, property),
        ],
      ],
    );
  }

  Widget _buildManagementTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Despesas', Icons.payments_outlined),
        const SizedBox(height: 10),
        _buildExpensesSection(context, theme, property),
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Checklists', Icons.checklist_rtl_rounded),
        const SizedBox(height: 10),
        _buildChecklistsSection(context, theme, property),
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Documentos', Icons.folder_open_outlined),
        const SizedBox(height: 10),
        _buildDocumentsSection(context, theme, property),
        const SizedBox(height: 22),
        _buildSectionHeader(theme, 'Publicação no site', Icons.public_outlined),
        const SizedBox(height: 10),
        PropertyPublicToggle(
          propertyId: property.id,
          initialValue: property.isAvailableForSite ?? false,
          propertyStatus: property.status,
          isActive: property.isActive,
          imageCount: property.imageCount ?? property.images?.length ?? 0,
          onSuccess: () => _loadProperty(),
          onError: (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: AppColors.status.error,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.25,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  /// Descrição editorial — sem caixa, sem limite duro, com expand/collapse.
  ///
  /// Antes era um Container com border + sombra + stripe accent + texto
  /// sem limite, virando paredão infinito em imóveis com descrição
  /// longa.
  ///
  /// Agora delega ao `_ExpandableDescription`:
  /// - Texto vai DIRETO sobre o background (sem caixa cinza)
  /// - Régua accent fina à esquerda como ânfase editorial
  /// - Mostra ~5 linhas com **gradient fade** no rodapé indicando truncamento
  /// - Botão "Ver mais" / "Ver menos" — não corta o conteúdo, só recolhe
  Widget _buildDescriptionCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return _ExpandableDescription(text: property.description);
  }

  Widget _buildCharacteristicsCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;

    final items = <({IconData icon, String label, String value})>[
      (icon: _typeIcon(property.type), label: 'Tipo', value: property.type.label),
      if (property.totalArea > 0)
        (
          icon: Icons.square_foot_rounded,
          label: 'Área total',
          value: '${property.totalArea.toInt()} m²',
        ),
      if (property.builtArea != null && property.builtArea! > 0)
        (
          icon: Icons.crop_free_rounded,
          label: 'Área construída',
          value: '${property.builtArea!.toInt()} m²',
        ),
      if (property.bedrooms != null && property.bedrooms! > 0)
        (
          icon: Icons.king_bed_outlined,
          label: 'Quartos',
          value: '${property.bedrooms}',
        ),
      if (property.bathrooms != null && property.bathrooms! > 0)
        (
          icon: Icons.bathtub_outlined,
          label: 'Banheiros',
          value: '${property.bathrooms}',
        ),
      if (property.parkingSpaces != null && property.parkingSpaces! > 0)
        (
          icon: Icons.directions_car_filled_outlined,
          label: 'Vagas',
          value: '${property.parkingSpaces}',
        ),
    ];

    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.28 : 0.2),
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 78,
        ),
        itemBuilder: (_, i) {
          final it = items[i];
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: (isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary)
                  .withValues(alpha: isDark ? 0.55 : 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor.withValues(alpha: isDark ? 0.45 : 0.55),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(it.icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        it.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdditionalValuesCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final items = <({IconData icon, String label, double value, Color color})>[
      if (property.condominiumFee != null)
        (
          icon: Icons.apartment_rounded,
          label: 'Condomínio',
          value: property.condominiumFee!,
          color: AppColors.status.info,
        ),
      if (property.iptu != null)
        (
          icon: Icons.receipt_long_outlined,
          label: 'IPTU anual',
          value: property.iptu!,
          color: AppColors.status.warning,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor.withValues(alpha: isDark ? 0.55 : 0.78),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: items[i].color.withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(items[i].icon, size: 14, color: items[i].color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          items[i].label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _currencyFormatter.format(items[i].value),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: -0.4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < items.length - 1) const SizedBox(width: 10),
        ],
      ],
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
                final chk = _asStringKeyedMap(checklist) ?? const <String, dynamic>{};
                final checklistId = chk['id']?.toString() ?? '';
                final type = chk['type']?.toString() ?? 'sale';
                final status = chk['status']?.toString() ?? 'pending';
                final completionPercentage = _extractChecklistCompletionPercentage(
                  chk,
                );
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

  // ────────────────────────────── BOTTOM BAR & FAB ──────────────────────────────

  Widget _buildBottomActionBar(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final hasOffers = property.totalOffersCount != null &&
        property.totalOffersCount! > 0;
    final pendingOffers = property.pendingOffersCount ?? 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: isDark ? 0.94 : 0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor.withValues(alpha: isDark ? 0.62 : 0.85)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Para usuários comuns sem vínculo, o backend rejeita a edição —
              // então em vez do botão primário "Editar imóvel" exibimos
              // "Compartilhar link" como ação principal (visualização-pura).
              Expanded(
                child: _canEditProperty
                    ? _bottomActionPrimary(
                        context: context,
                        theme: theme,
                        icon: Icons.edit_rounded,
                        label: 'Editar imóvel',
                        accent: accent,
                        onTap: () => Navigator.of(context).pushNamed(
                          '/properties/${property.id}/edit',
                        ),
                      )
                    : _bottomActionPrimary(
                        context: context,
                        theme: theme,
                        icon: Icons.share_outlined,
                        label: 'Compartilhar link',
                        accent: accent,
                        onTap: () {
                          final url = property.code != null &&
                                  property.code!.isNotEmpty
                              ? 'imovel/${property.code}'
                              : 'imovel/${property.id}';
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copiado'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
              ),
              if (_canEditProperty) ...[
                const SizedBox(width: 8),
                _bottomActionGhost(
                  theme: theme,
                  muted: muted,
                  icon: Icons.share_outlined,
                  tooltip: 'Compartilhar link',
                  onTap: () {
                    final url = property.code != null && property.code!.isNotEmpty
                        ? 'imovel/${property.code}'
                        : 'imovel/${property.id}';
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link copiado'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(width: 8),
              _bottomActionGhost(
                theme: theme,
                muted: muted,
                icon: Icons.request_quote_outlined,
                tooltip: hasOffers ? 'Ofertas' : 'Sem ofertas',
                badge: pendingOffers > 0 ? pendingOffers : null,
                badgeColor: AppColors.status.warning,
                disabled: !hasOffers,
                onTap: hasOffers
                    ? () => Navigator.of(context).pushNamed(
                          '/properties/offers',
                          arguments: {'propertyId': widget.propertyId},
                        )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomActionPrimary({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomActionGhost({
    required ThemeData theme,
    required Color muted,
    required IconData icon,
    required String tooltip,
    int? badge,
    Color? badgeColor,
    bool disabled = false,
    VoidCallback? onTap,
  }) {
    final c = disabled ? muted.withValues(alpha: 0.4) : muted;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: disabled ? 0.04 : 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: c, size: 19),
                if (badge != null && badge > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor ?? AppColors.status.error,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollTopButton(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _detailsScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
                spreadRadius: -2,
              ),
            ],
          ),
          child: const Icon(
            Icons.keyboard_arrow_up_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Visualizador fullscreen — paridade com `imobx-front/PropertyGalleryFullscreenPage`.
///
/// - **`BoxFit.contain`**: a imagem é mostrada nas suas dimensões reais
///   (com letterbox em volta). Isso permite ao avaliador ver se a foto é
///   quadrada/retangular antes de aprovar — `cover` cortava as bordas e
///   escondia desproporções.
/// - **Pinch + double-tap zoom** via `InteractiveViewer` (até 5x).
/// - **Pill de metadados** (categoria + dimensões + ratio + badge "QUADRADA"
///   ou "NÃO QUADRADA") — ajuda o avaliador a decidir rapidamente.
/// - **Botão de excluir** disponível para usuários com permissão
///   `propertyApprovePublication`/`propertyApproveAvailability` ou roles
///   master/admin. Confirmação obrigatória antes do delete.
/// - Retorna `true` no pop quando alguma imagem foi deletada — a página
///   pai usa isso pra recarregar o property.
class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({
    required this.images,
    required this.initialIndex,
    required this.propertyId,
    this.canDelete = false,
  });

  final List<PropertyImage> images;
  final int initialIndex;
  final String propertyId;
  final bool canDelete;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late List<PropertyImage> _images;
  late int _index;
  bool _didMutate = false;
  bool _deleting = false;

  /// Cache de dimensões reais (decodificadas) por url. Evita resolver de
  /// novo a cada rebuild e permite mostrar o ratio na barra inferior.
  final Map<String, Size> _resolvedSizes = {};

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.images);
    _index = widget.initialIndex.clamp(0, _images.length - 1);
    _controller = PageController(initialPage: _index);
    _resolveSizeFor(_currentImage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  PropertyImage? get _currentImage =>
      (_images.isEmpty || _index < 0 || _index >= _images.length)
          ? null
          : _images[_index];

  /// Resolve dimensões reais via `Image.image.resolve(...)` — apenas uma
  /// vez por URL. Útil pro badge "QUADRADA"/"NÃO QUADRADA" e pra mostrar
  /// "1920×1080" na pill inferior.
  void _resolveSizeFor(PropertyImage? img) {
    if (img == null) return;
    if (_resolvedSizes.containsKey(img.url)) return;
    final provider = NetworkImage(img.url);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _resolvedSizes[img.url] = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  bool _isApproximatelySquare(Size size) {
    if (size.width == 0 || size.height == 0) return false;
    final ratio = size.width / size.height;
    // Toleramos ±2% pra absorver compressões e arredondamentos JPEG.
    return (ratio - 1.0).abs() <= 0.02;
  }

  String _categoryLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'Geral';
    switch (raw.toLowerCase()) {
      case 'general':
        return 'Geral';
      case 'living_room':
      case 'sala':
        return 'Sala';
      case 'kitchen':
      case 'cozinha':
        return 'Cozinha';
      case 'bedroom':
      case 'quarto':
        return 'Quarto';
      case 'bathroom':
      case 'banheiro':
        return 'Banheiro';
      case 'facade':
      case 'fachada':
        return 'Fachada';
      case 'plant':
      case 'planta':
        return 'Planta';
      case 'leisure':
      case 'lazer':
        return 'Lazer';
      default:
        return raw[0].toUpperCase() + raw.substring(1);
    }
  }

  Future<void> _confirmAndDelete() async {
    if (!widget.canDelete || _deleting) return;
    final img = _currentImage;
    if (img == null || img.id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Excluir esta foto?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          img.isMain
              ? 'Esta é a foto principal. Ao excluir, a próxima imagem assume como principal automaticamente. Esta ação não pode ser desfeita.'
              : 'A imagem será removida do imóvel e do armazenamento. Esta ação não pode ser desfeita.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);

    final res = await GalleryService.instance.deleteImage(img.id);

    if (!mounted) return;

    if (!res.success) {
      setState(() => _deleting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            res.message ?? 'Não foi possível excluir a imagem.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _images.removeAt(_index);
      _didMutate = true;
      if (_images.isEmpty) {
        _index = 0;
      } else if (_index >= _images.length) {
        _index = _images.length - 1;
      }
      _deleting = false;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF3FA66B),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Foto excluída com sucesso.',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );

    if (_images.isEmpty) {
      Navigator.of(context).pop(_didMutate);
      return;
    }

    // Garante que o PageController acompanhe o novo índice
    _controller.jumpToPage(_index);
    _resolveSizeFor(_currentImage);
  }

  @override
  Widget build(BuildContext context) {
    final total = _images.length;
    final current = _currentImage;
    final size = current != null ? _resolvedSizes[current.url] : null;
    final isSquare = size != null && _isApproximatelySquare(size);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ───────── Imagem em dimensões reais (BoxFit.contain) ─────────
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(_didMutate),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _resolveSizeFor(_currentImage);
                  },
                  itemBuilder: (_, i) {
                    return Hero(
                      tag: 'property-image-${widget.propertyId}-$i',
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Center(
                          child: ShimmerImage(
                            imageUrl: _images[i].url,
                            // `contain` revela letterbox/pillarbox =
                            // o avaliador percebe imagens não-quadradas
                            // só de olhar.
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ───────── Top bar (fechar + counter + delete) ─────────
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  _GalleryRoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(_didMutate),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${_index + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  if (widget.canDelete && current != null) ...[
                    const SizedBox(width: 10),
                    _GalleryRoundIconButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: _confirmAndDelete,
                      // Vermelho semitransparente — "destrutivo" sem
                      // berrar como vermelho puro num fundo preto.
                      tint: AppColors.status.error,
                      busy: _deleting,
                    ),
                  ],
                ],
              ),
            ),

            // ───────── Badge de proporção (NÃO QUADRADA) ─────────
            // Aparece só quando temos as dimensões e a foto NÃO é quadrada.
            // Quadrada não recebe badge — evita ruído visual.
            if (size != null && !isSquare)
              Positioned(
                top: 60,
                right: 16,
                child: _RatioWarningBadge(),
              ),

            // ───────── Pill de metadados (bottom) ─────────
            if (current != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: total > 1 ? 60 : 26,
                child: _MetaPill(
                  category: _categoryLabel(current.category),
                  size: size,
                  isSquare: size != null ? isSquare : null,
                  isMain: current.isMain,
                ),
              ),

            // ───────── Dots (paginação) ─────────
            if (total > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 26,
                child: Center(
                  child: Wrap(
                    spacing: 6,
                    children: List.generate(total, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill com metadados (categoria + dimensões + ratio + foto principal).
///
/// Renderiza tudo em uma linha só — fluido. Os "chips" internos têm cores
/// distintas por função: categoria neutra, dimensões accent-cinza, ratio
/// verde se quadrada/cinza se desconhecido, "PRINCIPAL" amarelo.
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.category,
    required this.size,
    required this.isSquare,
    required this.isMain,
  });

  final String category;
  final Size? size;
  final bool? isSquare;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    final w = size?.width.toInt();
    final h = size?.height.toInt();
    final dimsLabel = (w != null && h != null) ? '$w × $h' : null;
    String? ratioLabel;
    if (size != null && size!.height > 0) {
      final r = size!.width / size!.height;
      ratioLabel = '${r.toStringAsFixed(2)}:1';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MetaChip(
            icon: Icons.category_outlined,
            label: category,
          ),
          if (dimsLabel != null)
            _MetaChip(
              icon: Icons.aspect_ratio_rounded,
              label: dimsLabel,
            ),
          if (ratioLabel != null)
            _MetaChip(
              icon: isSquare == true
                  ? Icons.crop_square_rounded
                  : Icons.crop_landscape_rounded,
              label: ratioLabel,
              tint: isSquare == true
                  ? const Color(0xFF3FA66B)
                  : const Color(0xFFE0AA3E),
            ),
          if (isMain)
            const _MetaChip(
              icon: Icons.star_rounded,
              label: 'PRINCIPAL',
              tint: Color(0xFFE0AA3E),
              emphasized: true,
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.tint,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Color? tint;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emphasized
            ? c.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: emphasized ? 1.2 : 0.2,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge "NÃO QUADRADA" — chama atenção pro avaliador no canto superior
/// direito quando a imagem foge da proporção quadrada (regra prioritária
/// pedida pelo time de aprovação).
class _RatioWarningBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE0AA3E).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0AA3E)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Color(0xFFE0AA3E),
          ),
          SizedBox(width: 6),
          Text(
            'NÃO QUADRADA',
            style: TextStyle(
              color: Color(0xFFE0AA3E),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryRoundIconButton extends StatelessWidget {
  const _GalleryRoundIconButton({
    required this.icon,
    required this.onTap,
    this.tint,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Cor de destaque opcional (usada na ação destrutiva de excluir).
  /// Quando setada, o botão herda essa cor no fundo (com alpha) e na borda.
  final Color? tint;

  /// Quando `true`, mostra spinner em lugar do ícone e desabilita o tap.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hasTint = tint != null;
    final fg = hasTint ? tint! : Colors.white;
    final bg = hasTint
        ? tint!.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.55);
    final borderColor = hasTint
        ? tint!.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.18);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              : Icon(icon, color: fg, size: 22),
        ),
      ),
    );
  }
}

/// Descrição editorial expansível.
///
/// Comportamento:
/// - **Recolhida**: mostra ~5 linhas; quando o texto extrapola, aplica
///   um `ShaderMask` com gradient fade no rodapé indicando que tem mais
///   conteúdo, e exibe o botão "Ver mais".
/// - **Expandida**: texto completo + botão "Ver menos".
/// - **Vazia**: mensagem discreta em itálico, sem qualquer caixa.
///
/// A detecção de "extrapolou as 5 linhas" é feita via `TextPainter.didExceedMaxLines`
/// no `LayoutBuilder` — assim o botão só aparece se realmente o texto
/// for longo o suficiente para ser truncado.
class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});

  final String text;

  static const int _kCollapsedMaxLines = 5;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final cleaned = widget.text.trim();
    final empty = cleaned.isEmpty;

    if (empty) {
      return Padding(
        padding: const EdgeInsets.only(left: 14, top: 4),
        child: Row(
          children: [
            Icon(Icons.short_text_rounded, size: 16, color: secondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Sem descrição cadastrada. Edite o imóvel para adicionar contexto.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.6,
      fontSize: 14.5,
      letterSpacing: -0.05,
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w500,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Régua accent fina à esquerda — referência editorial discreta
        Container(
          width: 3,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Mede se o texto extrapola N linhas pra decidir se
              // mostra o botão "Ver mais"/"Ver menos".
              final tp = TextPainter(
                text: TextSpan(text: cleaned, style: textStyle),
                maxLines: _ExpandableDescription._kCollapsedMaxLines,
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);

              final overflow = tp.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topLeft,
                    curve: Curves.easeOut,
                    child: _expanded || !overflow
                        ? SelectableText(
                            cleaned,
                            style: textStyle,
                          )
                        : ShaderMask(
                            shaderCallback: (rect) {
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: const [
                                  Colors.white,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.7, 1.0],
                              ).createShader(rect);
                            },
                            blendMode: BlendMode.dstIn,
                            child: Text(
                              cleaned,
                              maxLines: _ExpandableDescription._kCollapsedMaxLines,
                              overflow: TextOverflow.clip,
                              style: textStyle,
                            ),
                          ),
                  ),
                  if (overflow) ...[
                    const SizedBox(height: 6),
                    _ExpandToggle(
                      expanded: _expanded,
                      accent: accent,
                      onTap: () {
                        setState(() => _expanded = !_expanded);
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Botão minimalista de toggle "Ver mais ↓ / Ver menos ↑".
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  final bool expanded;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? 'Ver menos' : 'Ver mais',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
