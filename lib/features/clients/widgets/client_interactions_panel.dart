import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_button.dart';
import '../services/client_service.dart';
import '../models/client_model.dart';

/// Painel de interações com cliente
class ClientInteractionsPanel extends StatefulWidget {
  final String clientId;

  const ClientInteractionsPanel({
    super.key,
    required this.clientId,
  });

  @override
  State<ClientInteractionsPanel> createState() => _ClientInteractionsPanelState();
}

class _ClientInteractionsPanelState extends State<ClientInteractionsPanel> {
  final ClientService _clientService = ClientService.instance;
  List<ClientInteraction> _interactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInteractions();
  }

  Future<void> _loadInteractions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _clientService.getClientInteractions(widget.clientId);
      
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _interactions = response.data!;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar interações';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro de conexão';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateInteractionModal() async {
    // TODO: Implementar modal de criação de interação
    // Por enquanto, apenas mostra um snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Funcionalidade em desenvolvimento'),
          backgroundColor: AppColors.status.info,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        final cardMargin = isSmallScreen ? 8.0 : 16.0;
        final cardPadding = isSmallScreen ? 12.0 : 20.0;

        return Card(
          margin: EdgeInsets.all(cardMargin),
          child: Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isSmallScreen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                color: AppColors.primary.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Interações',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: ThemeHelpers.textColor(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CustomButton(
                            text: 'Nova Interação',
                            icon: Icons.add,
                            onPressed: _showCreateInteractionModal,
                            width: double.infinity,
                            isFullWidth: true,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.history,
                            color: AppColors.primary.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Interações',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                          ),
                          CustomButton(
                            text: 'Nova Interação',
                            icon: Icons.add,
                            onPressed: _showCreateInteractionModal,
                            width: null,
                            isFullWidth: false,
                          ),
                        ],
                      ),
                SizedBox(height: isSmallScreen ? 16 : 20),
                if (_isLoading)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                      child: const CircularProgressIndicator(),
                    ),
                  )
                else if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: isSmallScreen ? 36 : 48,
                            color: AppColors.status.error,
                          ),
                          SizedBox(height: isSmallScreen ? 8 : 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: isSmallScreen ? 13 : null,
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 12 : 16),
                          OutlinedButton(
                            onPressed: _loadInteractions,
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_interactions.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_outlined,
                            size: isSmallScreen ? 36 : 48,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          SizedBox(height: isSmallScreen ? 8 : 12),
                          Text(
                            'Nenhuma interação registrada',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontSize: isSmallScreen ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _interactions.length,
                      itemBuilder: (context, index) {
                        final interaction = _interactions[index];
                        return _buildInteractionCard(
                          context,
                          theme,
                          interaction,
                          isSmallScreen,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInteractionCard(
    BuildContext context,
    ThemeData theme,
    ClientInteraction interaction,
    bool isSmallScreen,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
      child: isSmallScreen
          ? Padding(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: isSmallScreen ? 18 : 20,
                        backgroundColor: AppColors.primary.primary.withOpacity(0.1),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          color: AppColors.primary.primary,
                          size: isSmallScreen ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          interaction.title ?? 'Sem título',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                            fontSize: isSmallScreen ? 14 : null,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) {
                          if (value == 'edit') {
                            // TODO: Implementar edição
                          } else if (value == 'delete') {
                            _deleteInteraction(interaction);
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
                  ),
                  const SizedBox(height: 12),
                  Text(
                    interaction.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontSize: isSmallScreen ? 12 : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (interaction.interactionAt != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(interaction.interactionAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: isSmallScreen ? 11 : null,
                              ),
                            ),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              interaction.createdBy?.name ?? 'Usuário',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: isSmallScreen ? 11 : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (interaction.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: interaction.attachments.map((attachment) {
                        return Chip(
                          label: Text(
                            attachment.name ?? 'Anexo',
                            style: TextStyle(fontSize: isSmallScreen ? 11 : null),
                          ),
                          avatar: Icon(Icons.attach_file, size: isSmallScreen ? 14 : 16),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 6 : 8,
                            vertical: isSmallScreen ? 4 : 6,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            )
          : ListTile(
              contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.primary.withOpacity(0.1),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: AppColors.primary.primary,
                ),
              ),
              title: Text(
                interaction.title ?? 'Sem título',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    interaction.notes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (interaction.interactionAt != null) ...[
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(interaction.interactionAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        interaction.createdBy?.name ?? 'Usuário',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                  if (interaction.attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: interaction.attachments.map((attachment) {
                        return Chip(
                          label: Text(attachment.name ?? 'Anexo'),
                          avatar: const Icon(Icons.attach_file, size: 16),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') {
                    // TODO: Implementar edição
                  } else if (value == 'delete') {
                    _deleteInteraction(interaction);
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
            ),
    );
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (e) {
      return dateTime;
    }
  }

  Future<void> _deleteInteraction(ClientInteraction interaction) async {
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tem certeza que deseja excluir esta interação?',
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

    if (confirmed == true) {
      final response = await _clientService.deleteClientInteraction(
        widget.clientId,
        interaction.id,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Interação excluída com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadInteractions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir interação'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    }
  }
}

