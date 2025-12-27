import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/services/property_offers_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Página de listagem de ofertas de propriedades
class PropertyOffersPage extends StatefulWidget {
  final String?
  propertyId; // Se fornecido, filtra apenas ofertas desta propriedade

  const PropertyOffersPage({super.key, this.propertyId});

  @override
  State<PropertyOffersPage> createState() => _PropertyOffersPageState();
}

class _PropertyOffersPageState extends State<PropertyOffersPage> {
  final PropertyOffersService _offersService = PropertyOffersService.instance;
  bool _isLoading = true;
  List<PropertyOffer> _offers = [];
  String? _errorMessage;

  // Filtros
  String? _selectedStatus;
  String? _selectedType;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint('💰 [OFFERS_PAGE] initState chamado');
    debugPrint('💰 [OFFERS_PAGE] propertyId: ${widget.propertyId}');
    _loadOffers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    debugPrint('💰 [OFFERS_PAGE] Iniciando carregamento de ofertas...');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filters = OfferFilters(
        propertyId: widget.propertyId,
        status: _selectedStatus,
        type: _selectedType,
      );

      debugPrint(
        '💰 [OFFERS_PAGE] Filtros: propertyId=${filters.propertyId}, status=${filters.status}, type=${filters.type}',
      );
      debugPrint('💰 [OFFERS_PAGE] Chamando getAllOffers...');

      final response = await _offersService.getAllOffers(filters: filters);

      debugPrint('💰 [OFFERS_PAGE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data is null: ${response.data == null}');
      debugPrint('   - data type: ${response.data?.runtimeType}');

      if (response.data != null && response.data is List) {
        debugPrint('   - data length: ${(response.data as List).length}');
      }

      if (mounted) {
        if (response.success && response.data != null) {
          try {
            // Verificar se é uma lista
            if (response.data is List) {
              final dataList = response.data as List;
              debugPrint(
                '💰 [OFFERS_PAGE] Dados são uma lista com ${dataList.length} itens',
              );

              // Verificar se todos os itens são PropertyOffer
              final offers = <PropertyOffer>[];
              for (var i = 0; i < dataList.length; i++) {
                final item = dataList[i];
                if (item is PropertyOffer) {
                  offers.add(item);
                } else {
                  debugPrint(
                    '⚠️ [OFFERS_PAGE] Item $i não é PropertyOffer: ${item.runtimeType}',
                  );
                }
              }

              debugPrint(
                '✅ [OFFERS_PAGE] ${offers.length} ofertas carregadas com sucesso',
              );
              setState(() {
                _offers = offers;
                _isLoading = false;
              });
            } else {
              debugPrint(
                '❌ [OFFERS_PAGE] Dados não são uma lista: ${response.data.runtimeType}',
              );
              if (mounted) {
                setState(() {
                  _errorMessage = 'Formato de dados inválido';
                  _isLoading = false;
                });
              }
            }
          } catch (castError, stackTrace) {
            debugPrint('❌ [OFFERS_PAGE] Erro ao processar dados: $castError');
            debugPrint('📚 [OFFERS_PAGE] StackTrace: $stackTrace');
            debugPrint(
              '📋 [OFFERS_PAGE] Tipo de dados: ${response.data.runtimeType}',
            );
            if (mounted) {
              setState(() {
                _errorMessage = 'Erro ao processar dados das ofertas';
                _isLoading = false;
              });
            }
          }
        } else {
          debugPrint('❌ [OFFERS_PAGE] Resposta não bem-sucedida ou sem dados');
          if (mounted) {
            setState(() {
              _errorMessage = response.message ?? 'Erro ao carregar ofertas';
              _isLoading = false;
            });
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [OFFERS_PAGE] Exceção capturada: $e');
      debugPrint('📚 [OFFERS_PAGE] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.propertyId != null ? 'Ofertas da Propriedade' : 'Ofertas',
      showBottomNavigation: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () => _showFiltersDialog(context),
          tooltip: 'Filtros',
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context)
          : _buildOffersList(context),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SkeletonCard(
          height: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(
                width: 200,
                height: 20,
                margin: const EdgeInsets.only(bottom: 8),
              ),
              SkeletonText(
                width: 150,
                height: 16,
                margin: const EdgeInsets.only(bottom: 8),
              ),
              SkeletonText(
                width: double.infinity,
                height: 16,
                margin: const EdgeInsets.only(bottom: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar ofertas',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadOffers,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffersList(BuildContext context) {
    final theme = Theme.of(context);

    if (_offers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.request_quote_outlined,
                size: 64,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhuma oferta encontrada',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOffers,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _offers.length,
        itemBuilder: (context, index) {
          final offer = _offers[index];
          return _buildOfferCard(context, theme, offer);
        },
      ),
    );
  }

  Widget _buildOfferCard(
    BuildContext context,
    ThemeData theme,
    PropertyOffer offer,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pushNamed('/properties/offers/${offer.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com título e status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                border: Border(
                  bottom: BorderSide(
                    color: ThemeHelpers.borderColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              offer.type == 'sale'
                                  ? Icons.sell_outlined
                                  : Icons.home_work_outlined,
                              size: 18,
                              color: AppColors.primary.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              offer.type == 'sale' ? 'Venda' : 'Aluguel',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          offer.property?.title ??
                              'Propriedade #${offer.propertyId}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ThemeHelpers.textColor(context),
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(
                        offer.status,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(
                          offer.status,
                        ).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _getStatusLabel(offer.status),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _getStatusColor(offer.status),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Valores
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor oferecido (destaque)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.primary.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Valor Oferecido',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _currencyFormatter.format(offer.offeredValue),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary.primary,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Comparação com preço original
                  if (offer.property != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preço Original',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                offer.type == 'sale'
                                    ? (offer.property!.salePrice != null
                                          ? _currencyFormatter.format(
                                              offer.property!.salePrice!,
                                            )
                                          : '-')
                                    : (offer.property!.rentPrice != null
                                          ? _currencyFormatter.format(
                                              offer.property!.rentPrice!,
                                            )
                                          : '-'),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                  decoration: TextDecoration.lineThrough,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (offer.property!.salePrice != null ||
                            offer.property!.rentPrice != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  offer.offeredValue <
                                      (offer.type == 'sale'
                                          ? (offer.property!.salePrice ?? 0)
                                          : (offer.property!.rentPrice ?? 0))
                                  ? AppColors.status.warning.withValues(
                                      alpha: 0.1,
                                    )
                                  : AppColors.status.success.withValues(
                                      alpha: 0.1,
                                    ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              offer.offeredValue <
                                      (offer.type == 'sale'
                                          ? (offer.property!.salePrice ?? 0)
                                          : (offer.property!.rentPrice ?? 0))
                                  ? 'Abaixo'
                                  : 'Acima',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    offer.offeredValue <
                                        (offer.type == 'sale'
                                            ? (offer.property!.salePrice ?? 0)
                                            : (offer.property!.rentPrice ?? 0))
                                    ? AppColors.status.warning
                                    : AppColors.status.success,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Informações do cliente
            if (offer.publicUser != null) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderColor(context),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: AppColors.primary.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cliente',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            offer.publicUser!.email,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (offer.publicUser!.phone.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              offer.publicUser!.phone,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Mensagem
            if (offer.message != null && offer.message!.isNotEmpty) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderColor(context),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.message_outlined,
                          size: 16,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Mensagem',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.background.backgroundSecondaryDarkMode
                            : AppColors.background.backgroundSecondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        offer.message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 13,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Footer com data
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_outlined,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Criada em ${_formatDate(offer.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.status.warning;
      case 'accepted':
        return AppColors.status.success;
      case 'rejected':
        return AppColors.status.error;
      case 'withdrawn':
        return AppColors.text.textSecondary;
      case 'expired':
        return AppColors.text.textSecondary;
      default:
        return AppColors.text.textSecondary;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'accepted':
        return 'Aceita';
      case 'rejected':
        return 'Rejeitada';
      case 'withdrawn':
        return 'Retirada';
      case 'expired':
        return 'Expirada';
      default:
        return status;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date);
    } catch (e) {
      return dateString;
    }
  }

  void _showFiltersDialog(BuildContext context) {
    showModalBottomSheet(
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
                        'Filtros',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    const DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pendente'),
                    ),
                    const DropdownMenuItem(
                      value: 'accepted',
                      child: Text('Aceita'),
                    ),
                    const DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejeitada'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    const DropdownMenuItem(value: 'sale', child: Text('Venda')),
                    const DropdownMenuItem(
                      value: 'rental',
                      child: Text('Aluguel'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _loadOffers();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.filter_alt),
                        label: const Text('Aplicar Filtros'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedStatus = null;
                                _selectedType = null;
                              });
                              _loadOffers();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancelar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
