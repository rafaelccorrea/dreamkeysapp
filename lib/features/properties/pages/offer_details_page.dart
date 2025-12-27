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

/// Página de detalhes de uma oferta
class OfferDetailsPage extends StatefulWidget {
  final String offerId;

  const OfferDetailsPage({
    super.key,
    required this.offerId,
  });

  @override
  State<OfferDetailsPage> createState() => _OfferDetailsPageState();
}

class _OfferDetailsPageState extends State<OfferDetailsPage> {
  final PropertyOffersService _offersService = PropertyOffersService.instance;
  bool _isLoading = true;
  PropertyOffer? _offer;
  String? _errorMessage;
  bool _isProcessing = false;
  final TextEditingController _responseMessageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  @override
  void dispose() {
    _responseMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadOffer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _offersService.getOfferById(widget.offerId);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _offer = response.data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar oferta';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [OFFER_DETAILS] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateOfferStatus(String status) async {
    if (_offer == null) return;

    final responseMessage = _responseMessageController.text.trim();
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await _offersService.updateOfferStatus(
        offerId: widget.offerId,
        status: status,
        responseMessage: responseMessage.isEmpty ? null : responseMessage,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == 'accepted' ? 'Oferta aceita com sucesso!' : 'Oferta rejeitada',
              ),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadOffer(); // Recarregar dados
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar oferta'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao atualizar oferta: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao conectar com o servidor')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showActionDialog(String action) {
    if (_offer == null) return;

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
                    Expanded(
                      child: Text(
                        action == 'accepted' ? 'Aceitar Oferta' : 'Rejeitar Oferta',
                        style: const TextStyle(
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
                Text(
                  action == 'accepted'
                      ? 'Tem certeza que deseja aceitar esta oferta?'
                      : 'Tem certeza que deseja rejeitar esta oferta?',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _responseMessageController,
                  decoration: const InputDecoration(
                    labelText: 'Mensagem de resposta (opcional)',
                    hintText: 'Mensagem que será enviada ao ofertante',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _updateOfferStatus(action);
                        },
                        icon: Icon(action == 'accepted' ? Icons.check_circle : Icons.cancel),
                        label: Text(action == 'accepted' ? 'Aceitar Oferta' : 'Rejeitar Oferta'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: action == 'accepted'
                              ? AppColors.status.success
                              : AppColors.status.error,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
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
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Detalhes da Oferta',
      showBottomNavigation: false,
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : _offer != null
          ? _buildOfferDetails(context, theme, _offer!)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonText(width: 250, height: 24, margin: const EdgeInsets.only(bottom: 16)),
          SkeletonCard(
            height: 200,
            child: Column(
              children: List.generate(4, (index) => Padding(
                padding: EdgeInsets.only(bottom: index < 3 ? 16 : 0),
                child: Row(
                  children: [
                    SkeletonBox(width: 24, height: 24, borderRadius: 12),
                    const SizedBox(width: 12),
                    SkeletonText(width: 100, height: 16),
                    const Spacer(),
                    SkeletonText(width: 80, height: 16),
                  ],
                ),
              )),
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
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.status.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar oferta',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadOffer,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferDetails(BuildContext context, ThemeData theme, PropertyOffer offer) {
    final canAccept = offer.status == 'pending';
    final canReject = offer.status == 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status e tipo
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(offer.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getStatusLabel(offer.status),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _getStatusColor(offer.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  offer.type == 'sale' ? 'Venda' : 'Aluguel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Propriedade
          if (offer.property != null) ...[
            Text(
              'Propriedade',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: Text(offer.property!.title),
                subtitle: Text('ID: ${offer.property!.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/properties/${offer.property!.id}',
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Valores
          Text(
            'Valores',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildValueRow(
                    theme,
                    'Valor Oferecido',
                    _currencyFormatter.format(offer.offeredValue),
                    AppColors.primary.primary,
                    isBold: true,
                  ),
                  if (offer.property != null) ...[
                    const Divider(),
                    _buildValueRow(
                      theme,
                      'Preço Original',
                      offer.type == 'sale'
                          ? (offer.property!.salePrice != null
                              ? _currencyFormatter.format(offer.property!.salePrice)
                              : '-')
                          : (offer.property!.rentPrice != null
                              ? _currencyFormatter.format(offer.property!.rentPrice)
                              : '-'),
                      ThemeHelpers.textSecondaryColor(context),
                    ),
                    const Divider(),
                    _buildValueRow(
                      theme,
                      'Diferença',
                      _calculateDifference(offer),
                      _getDifferenceColor(offer),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Ofertante
          if (offer.publicUser != null) ...[
            Text(
              'Ofertante',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(offer.publicUser!.email),
                subtitle: Text(offer.publicUser!.phone),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Mensagem do ofertante
          if (offer.message != null && offer.message!.isNotEmpty) ...[
            Text(
              'Mensagem do Ofertante',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  offer.message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Resposta (se houver)
          if (offer.responseMessage != null && offer.responseMessage!.isNotEmpty) ...[
            Text(
              'Resposta',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  offer.responseMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Informações
          Text(
            'Informações',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow(theme, 'Criada em', _formatDate(offer.createdAt)),
                  if (offer.respondedAt != null)
                    _buildInfoRow(theme, 'Respondida em', _formatDate(offer.respondedAt!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Ações
          if (canAccept || canReject) ...[
            Row(
              children: [
                if (canReject)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _showActionDialog('rejected'),
                      icon: const Icon(Icons.close),
                      label: const Text('Rejeitar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.status.error,
                      ),
                    ),
                  ),
                if (canReject && canAccept) const SizedBox(width: 12),
                if (canAccept)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _showActionDialog('accepted'),
                      icon: const Icon(Icons.check),
                      label: const Text('Aceitar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.status.success,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValueRow(
    ThemeData theme,
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
  }) {
    return Row(
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
          style: theme.textTheme.bodyLarge?.copyWith(
            color: valueColor,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
            ),
          ),
        ],
      ),
    );
  }

  String _calculateDifference(PropertyOffer offer) {
    if (offer.property == null) return '-';
    
    final originalPrice = offer.type == 'sale'
        ? offer.property!.salePrice
        : offer.property!.rentPrice;
    
    if (originalPrice == null) return '-';
    
    final difference = offer.offeredValue - originalPrice;
    final percentage = (difference / originalPrice) * 100;
    
    return '${difference >= 0 ? '+' : ''}${_currencyFormatter.format(difference)} (${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(1)}%)';
  }

  Color _getDifferenceColor(PropertyOffer offer) {
    if (offer.property == null) return ThemeHelpers.textSecondaryColor(context);
    
    final originalPrice = offer.type == 'sale'
        ? offer.property!.salePrice
        : offer.property!.rentPrice;
    
    if (originalPrice == null) return ThemeHelpers.textSecondaryColor(context);
    
    final difference = offer.offeredValue - originalPrice;
    
    if (difference > 0) return AppColors.status.success;
    if (difference < 0) return AppColors.status.error;
    return ThemeHelpers.textSecondaryColor(context);
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
}

