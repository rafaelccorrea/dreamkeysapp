import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../shared/widgets/custom_button.dart';
import '../services/client_service.dart';
import '../models/client_model.dart';
import '../widgets/transfer_client_modal.dart';
import '../widgets/client_interactions_panel.dart';
import '../../../shared/utils/masks.dart';

/// Página de detalhes do cliente
class ClientDetailsPage extends StatefulWidget {
  final String clientId;

  const ClientDetailsPage({super.key, required this.clientId});

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage> {
  final ClientService _clientService = ClientService.instance;
  Client? _client;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Future<void> _loadClient() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _clientService.getClientById(widget.clientId);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _client = response.data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar cliente';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showTransferModal() async {
    if (_client == null || !mounted) return;

    final result = await showDialog(
      context: context,
      builder: (context) => TransferClientModal(
        clientId: _client!.id,
        clientName: _client!.name,
        currentResponsibleUserId: _client!.responsibleUserId,
        currentResponsibleName: _client!.responsibleUser?.name,
      ),
    );

    if (result == true) {
      _loadClient();
    }
  }

  Future<void> _deleteClient() async {
    final confirmed = await showModalBottomSheet<bool>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: AppColors.status.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Confirmar Exclusão',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Tem certeza que deseja excluir este cliente?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.status.error,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Excluir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && _client != null) {
      final response = await _clientService.deleteClient(_client!.id);

      if (mounted) {
        if (response.success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente excluído com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir cliente'),
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
      title: 'Detalhes do Cliente',
      actions: [
        if (_client != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  Navigator.pushNamed(
                    context,
                    AppRoutes.clientEdit(_client!.id),
                  );
                  break;
                case 'transfer':
                  _showTransferModal();
                  break;
                case 'delete':
                  _deleteClient();
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
              const PopupMenuItem(
                value: 'transfer',
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 20),
                    SizedBox(width: 8),
                    Text('Transferir'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Excluir', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
      ],
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null && _client == null
          ? _buildErrorState(context, theme)
          : _client == null
          ? _buildErrorState(context, theme)
          : RefreshIndicator(
              onRefresh: _loadClient,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width < 400 ? 16 : 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    _buildHeader(context, theme),
                    SizedBox(
                      height: MediaQuery.of(context).size.width < 400 ? 16 : 24,
                    ),
                    // Informações Básicas
                    _buildBasicInfo(context, theme),
                    SizedBox(
                      height: MediaQuery.of(context).size.width < 400 ? 16 : 24,
                    ),
                    // Endereço
                    _buildAddressInfo(context, theme),
                    SizedBox(
                      height: MediaQuery.of(context).size.width < 400 ? 16 : 24,
                    ),
                    // Informações Profissionais
                    if (_client!.employmentStatus != null ||
                        _client!.companyName != null)
                      _buildProfessionalInfo(context, theme),
                    if (_client!.employmentStatus != null ||
                        _client!.companyName != null)
                      const SizedBox(height: 24),
                    // Informações Financeiras
                    if (_client!.monthlyIncome != null ||
                        _client!.creditScore != null)
                      _buildFinancialInfo(context, theme),
                    if (_client!.monthlyIncome != null ||
                        _client!.creditScore != null)
                      const SizedBox(height: 24),
                    // Preferências Imobiliárias
                    if (_client!.preferredPropertyType != null ||
                        _client!.minValue != null)
                      _buildPreferencesInfo(context, theme),
                    if (_client!.preferredPropertyType != null ||
                        _client!.minValue != null)
                      const SizedBox(height: 24),
                    // Cônjuge
                    if (_client!.spouse != null)
                      _buildSpouseInfo(context, theme),
                    if (_client!.spouse != null) const SizedBox(height: 24),
                    // Observações
                    if (_client!.notes != null && _client!.notes!.isNotEmpty)
                      _buildNotesInfo(context, theme),
                    if (_client!.notes != null && _client!.notes!.isNotEmpty)
                      const SizedBox(height: 24),
                    // Interações
                    ClientInteractionsPanel(clientId: _client!.id),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                SkeletonBox(width: 120, height: 120, borderRadius: 60),
                const SizedBox(height: 20),
                SkeletonBox(width: 200, height: 24, borderRadius: 8),
                const SizedBox(height: 8),
                SkeletonBox(width: 150, height: 16, borderRadius: 8),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180, height: 20, borderRadius: 8),
                  const SizedBox(height: 16),
                  ...List.generate(
                    4,
                    (index) => Padding(
                      padding: EdgeInsets.only(bottom: index < 3 ? 16 : 0),
                      child: Row(
                        children: [
                          SkeletonBox(width: 40, height: 40, borderRadius: 10),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  width: 80,
                                  height: 14,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 4),
                                SkeletonBox(
                                  width: 120,
                                  height: 16,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar cliente',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Cliente não encontrado',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Voltar',
              icon: Icons.arrow_back,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final typeColor = _getTypeColor(_client!.type);
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [typeColor.withOpacity(0.15), typeColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(color: typeColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: isSmallScreen ? 80 : 100,
            height: isSmallScreen ? 80 : 100,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _client!.name.isNotEmpty ? _client!.name[0].toUpperCase() : '?',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 32 : 40,
                ),
              ),
            ),
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
          // Nome
          Text(
            _client!.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: ThemeHelpers.textColor(context),
              fontSize: isSmallScreen ? 20 : 24,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Badges
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _client!.type.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(_client!.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _client!.status.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _getStatusColor(_client!.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo(BuildContext context, ThemeData theme) {
    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Informações Básicas',
      children: [
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.email_outlined,
          label: 'Email',
          value: _client!.email,
        ),
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.phone_outlined,
          label: 'Telefone',
          value: _formatPhone(_client!.phone),
        ),
        if (_client!.secondaryPhone != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.phone_outlined,
            label: 'Telefone Secundário',
            value: _formatPhone(_client!.secondaryPhone!),
          ),
        if (_client!.whatsapp != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.chat_outlined,
            label: 'WhatsApp',
            value: _formatPhone(_client!.whatsapp!),
          ),
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.badge_outlined,
          label: 'CPF',
          value: _formatCpf(_client!.cpf),
          showDivider: false,
        ),
        if (_client!.birthDate != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.cake_outlined,
            label: 'Data de Nascimento',
            value: _formatDate(_client!.birthDate),
          ),
        if (_client!.maritalStatus != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.favorite_outline,
            label: 'Estado Civil',
            value: _client!.maritalStatus!.label,
            showDivider: false,
          ),
      ],
    );
  }

  Widget _buildAddressInfo(BuildContext context, ThemeData theme) {
    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Endereço',
      children: [
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.location_on_outlined,
          label: 'Endereço',
          value: _client!.address,
        ),
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.place_outlined,
          label: 'Bairro',
          value: _client!.neighborhood,
        ),
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.location_city_outlined,
          label: 'Cidade',
          value: '${_client!.city} - ${_client!.state}',
        ),
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.markunread_mailbox_outlined,
          label: 'CEP',
          value: Masks.cep(_client!.zipCode),
          showDivider: false,
        ),
      ],
    );
  }

  Widget _buildProfessionalInfo(BuildContext context, ThemeData theme) {
    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Informações Profissionais',
      children: [
        if (_client!.employmentStatus != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.work_outline,
            label: 'Situação Profissional',
            value: _client!.employmentStatus!.label,
          ),
        if (_client!.companyName != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.business_outlined,
            label: 'Empresa',
            value: _client!.companyName!,
          ),
        if (_client!.jobPosition != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.badge_outlined,
            label: 'Cargo',
            value: _client!.jobPosition!,
          ),
        if (_client!.isRetired == true)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.work_off_outlined,
            label: 'Aposentado',
            value: 'Sim',
            showDivider: false,
          ),
      ],
    );
  }

  Widget _buildFinancialInfo(BuildContext context, ThemeData theme) {
    final currencyFormat = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );

    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Informações Financeiras',
      children: [
        if (_client!.monthlyIncome != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.attach_money_outlined,
            label: 'Renda Mensal',
            value: currencyFormat.format(_client!.monthlyIncome!),
          ),
        if (_client!.familyIncome != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.account_balance_wallet_outlined,
            label: 'Renda Familiar',
            value: currencyFormat.format(_client!.familyIncome!),
          ),
        if (_client!.creditScore != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.credit_score_outlined,
            label: 'Score de Crédito',
            value: '${_client!.creditScore}/1000',
          ),
        if (_client!.bankName != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.account_balance_outlined,
            label: 'Banco',
            value: _client!.bankName!,
            showDivider: false,
          ),
      ],
    );
  }

  Widget _buildPreferencesInfo(BuildContext context, ThemeData theme) {
    final currencyFormat = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );

    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Preferências Imobiliárias',
      children: [
        if (_client!.preferredPropertyType != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.home_outlined,
            label: 'Tipo Preferido',
            value: _client!.preferredPropertyType!,
          ),
        if (_client!.preferredCity != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.location_city_outlined,
            label: 'Cidade Preferida',
            value: _client!.preferredCity!,
          ),
        if (_client!.minValue != null && _client!.maxValue != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.attach_money_outlined,
            label: 'Faixa de Preço',
            value:
                '${currencyFormat.format(_client!.minValue!)} - ${currencyFormat.format(_client!.maxValue!)}',
          ),
        if (_client!.minBedrooms != null && _client!.maxBedrooms != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.bed_outlined,
            label: 'Quartos',
            value: '${_client!.minBedrooms} - ${_client!.maxBedrooms}',
          ),
        if (_client!.minArea != null && _client!.maxArea != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.square_foot_outlined,
            label: 'Área (m²)',
            value:
                '${_client!.minArea!.toStringAsFixed(0)} - ${_client!.maxArea!.toStringAsFixed(0)}',
            showDivider: false,
          ),
      ],
    );
  }

  Widget _buildSpouseInfo(BuildContext context, ThemeData theme) {
    final spouse = _client!.spouse!;

    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Cônjuge',
      children: [
        _buildInfoItem(
          context: context,
          theme: theme,
          icon: Icons.person_outline,
          label: 'Nome',
          value: spouse.name,
        ),
        if (spouse.cpf != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.badge_outlined,
            label: 'CPF',
            value: _formatCpf(spouse.cpf!),
          ),
        if (spouse.phone != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.phone_outlined,
            label: 'Telefone',
            value: _formatPhone(spouse.phone!),
          ),
        if (spouse.email != null)
          _buildInfoItem(
            context: context,
            theme: theme,
            icon: Icons.email_outlined,
            label: 'Email',
            value: spouse.email!,
            showDivider: false,
          ),
      ],
    );
  }

  Widget _buildNotesInfo(BuildContext context, ThemeData theme) {
    return _buildInfoCard(
      context: context,
      theme: theme,
      title: 'Observações',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _client!.notes!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required List<Widget> children,
  }) {
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      margin: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 0 : 4,
        vertical: isSmallScreen ? 6 : 8,
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ThemeHelpers.textColor(context),
                      fontSize: isSmallScreen ? 16 : 18,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String value,
    bool showDivider = true,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
              child: isSmallScreen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                icon,
                                size: 16,
                                color: AppColors.primary.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 38),
                          child: Text(
                            value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            size: 20,
                            color: AppColors.primary.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                value,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderLightColor(context).withOpacity(0.5),
              ),
          ],
        );
      },
    );
  }

  Color _getTypeColor(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return AppColors.status.success;
      case ClientType.seller:
        return AppColors.status.warning;
      case ClientType.renter:
        return AppColors.primary.primary;
      case ClientType.lessor:
        return AppColors.status.info;
      case ClientType.investor:
        return Colors.purple;
      case ClientType.general:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  Color _getStatusColor(ClientStatus status) {
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

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '-';
    // Se já está formatado, retorna como está
    if (phone.contains('(') || phone.contains('-')) {
      return phone;
    }
    // Aplica máscara
    return Masks.phone(phone);
  }

  String _formatCpf(String? cpf) {
    if (cpf == null || cpf.isEmpty) return '-';
    // Remove qualquer formatação existente
    final digits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    // Se não tem 11 dígitos, retorna como está (pode ser inválido)
    if (digits.length != 11) return cpf;
    // Aplica máscara
    return Masks.cpf(digits);
  }
}
