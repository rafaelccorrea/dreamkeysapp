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
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com status e tipo
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundSecondaryDarkMode
                  : AppColors.background.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.border.borderDarkMode
                    : AppColors.border.border,
                width: 1,
              ),
            ),
            child: Row(
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
                            size: 20,
                            color: AppColors.primary.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            offer.type == 'sale' ? 'Venda' : 'Aluguel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        offer.property?.title ?? 'Propriedade #${offer.propertyId}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(offer.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _getStatusColor(offer.status).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _getStatusLabel(offer.status),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _getStatusColor(offer.status),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Valores (destaque)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundSecondaryDarkMode
                  : AppColors.background.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.border.borderDarkMode
                    : AppColors.border.border,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.attach_money_outlined,
                      size: 20,
                      color: AppColors.primary.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Valores',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Valor oferecido
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary.withValues(alpha: 0.1),
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
                      const SizedBox(height: 8),
                      Text(
                        _currencyFormatter.format(offer.offeredValue),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary.primary,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                if (offer.property != null) ...[
                  const SizedBox(height: 16),
                  // Preço original
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preço Original',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              offer.type == 'sale'
                                  ? (offer.property!.salePrice != null
                                      ? _currencyFormatter.format(offer.property!.salePrice!)
                                      : '-')
                                  : (offer.property!.rentPrice != null
                                      ? _currencyFormatter.format(offer.property!.rentPrice!)
                                      : '-'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                decoration: TextDecoration.lineThrough,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Diferença
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getDifferenceColor(offer).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getDifferenceColor(offer).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Diferença',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _calculateDifference(offer).split(' ').first,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _getDifferenceColor(offer),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Propriedade
          if (offer.property != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pushNamed(
                    '/properties/${offer.property!.id}',
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.home_outlined,
                          size: 24,
                          color: AppColors.primary.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Propriedade',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              offer.property!.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Ofertante
          if (offer.publicUser != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 20,
                        color: AppColors.primary.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ofertante',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person,
                          size: 24,
                          color: AppColors.primary.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              offer.publicUser!.email,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (offer.publicUser!.phone.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                offer.publicUser!.phone,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Mensagem do ofertante
          if (offer.message != null && offer.message!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 20,
                        color: AppColors.primary.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mensagem do Ofertante',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.background.backgroundSecondaryDarkMode
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      offer.message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Resposta (se houver)
          if (offer.responseMessage != null && offer.responseMessage!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.reply_outlined,
                        size: 20,
                        color: AppColors.status.success,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Resposta',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.status.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.status.success.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      offer.responseMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Informações
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundSecondaryDarkMode
                  : AppColors.background.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.border.borderDarkMode
                    : AppColors.border.border,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Informações',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow(theme, 'Criada em', _formatDate(offer.createdAt)),
                if (offer.respondedAt != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(theme, 'Respondida em', _formatDate(offer.respondedAt!)),
                ],
              ],
            ),
          ),

          // Ações
          if (canAccept || canReject) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (canAccept)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _showActionDialog('accepted'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Aceitar Oferta'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.status.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (canAccept && canReject) const SizedBox(height: 12),
                  if (canReject)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _showActionDialog('rejected'),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Rejeitar Oferta'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.status.error,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: AppColors.status.error,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.access_time_outlined,
              size: 16,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
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

