import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_button.dart';
import '../services/client_service.dart';
import '../models/client_model.dart';

/// Modal para transferir cliente para outro responsável
class TransferClientModal extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String? currentResponsibleUserId;
  final String? currentResponsibleName;
  final VoidCallback? onTransferComplete;

  const TransferClientModal({
    super.key,
    required this.clientId,
    required this.clientName,
    this.currentResponsibleUserId,
    this.currentResponsibleName,
    this.onTransferComplete,
  });

  @override
  State<TransferClientModal> createState() => _TransferClientModalState();
}

class _TransferClientModalState extends State<TransferClientModal> {
  final ClientService _clientService = ClientService.instance;
  List<UserInfo> _users = [];
  String? _selectedUserId;
  bool _isLoading = true;
  bool _isTransferring = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _clientService.getUsersForTransfer();
      
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _users = response.data!;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar usuários';
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

  Future<void> _handleTransfer() async {
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione um usuário para transferir'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isTransferring = true;
    });

    try {
      final response = await _clientService.transferClient(
        widget.clientId,
        _selectedUserId!,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          Navigator.of(context).pop();
          if (widget.onTransferComplete != null) {
            widget.onTransferComplete!();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cliente "${widget.clientName}" transferido com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao transferir cliente'),
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
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.primary.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    color: AppColors.primary.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transferir Cliente',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.clientName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.currentResponsibleName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ThemeHelpers.cardBackgroundColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ThemeHelpers.borderLightColor(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 20,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Responsável Atual',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.currentResponsibleName!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'Selecione o novo responsável:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_errorMessage != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppColors.status.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_users.isEmpty)
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
                                'Nenhum usuário disponível',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._users.map((user) {
                        final isSelected = _selectedUserId == user.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.primary.withOpacity(0.1)
                                : ThemeHelpers.cardBackgroundColor(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary.primary
                                  : ThemeHelpers.borderLightColor(context),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.primary.withOpacity(0.1),
                              child: Text(
                                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: AppColors.primary.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              user.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            subtitle: Text(
                              user.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary.primary,
                                  )
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedUserId = user.id;
                              });
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            // Botões
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isTransferring ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: CustomButton(
                      text: 'Transferir',
                      icon: Icons.swap_horiz,
                      onPressed: _isTransferring ? null : _handleTransfer,
                      isLoading: _isTransferring,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

