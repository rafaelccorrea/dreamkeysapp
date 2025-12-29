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
  bool _isLoading = true;
  Property? _property;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProperty();
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
                        color: AppColors.primary.primary.withValues(alpha: 0.15),
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
                                _currencyFormatter.format(property.salePrice).replaceAll('R\$', '').trim(),
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
                                _currencyFormatter.format(property.rentPrice).replaceAll('R\$', '').trim(),
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
                                  color: AppColors.primary.primary.withValues(alpha: 0.8),
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

                // Publicação no site
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

                // Ofertas (se houver)
                if (property.hasPendingOffers == true ||
                    property.totalOffersCount != null &&
                        property.totalOffersCount! > 0) ...[
                  _buildSectionTitle(theme, 'Ofertas'),
                  const SizedBox(height: 16),
                  _buildOffersSection(context, theme, property),
                  const SizedBox(height: 32),
                ],

                // Clientes associados (se houver)
                if (property.clients != null &&
                    property.clients!.isNotEmpty) ...[
                  _buildSectionTitle(theme, 'Clientes Interessados'),
                  const SizedBox(height: 16),
                  _buildClientsSection(context, theme, property.clients!),
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

    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        height: 300,
        color: Theme.of(context).brightness == Brightness.dark
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
      child: PageView.builder(
        itemCount: images.length,
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

  Widget _buildClientsSection(
    BuildContext context,
    ThemeData theme,
    List<PropertyClient> clients,
  ) {
    return Column(
      children: clients.take(5).map((client) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(child: Text(client.name[0].toUpperCase())),
            title: Text(client.name),
            subtitle: Text(client.email),
            trailing: Text(
              client.interestType,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary.primary,
              ),
            ),
          ),
        );
      }).toList(),
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
}
