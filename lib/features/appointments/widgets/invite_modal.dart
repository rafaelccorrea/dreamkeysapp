import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../controllers/appointment_controller.dart';

/// Modal para convidar usuários para um agendamento
class InviteModal extends StatefulWidget {
  final String appointmentId;
  final String appointmentTitle;

  const InviteModal({
    super.key,
    required this.appointmentId,
    required this.appointmentTitle,
  });

  @override
  State<InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<InviteModal> {
  final _messageController = TextEditingController();
  String? _selectedUserId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    // TODO: Implementar busca de usuários
    // Por enquanto, lista vazia
    setState(() {
      _isLoadingUsers = false;
    });
  }

  Future<void> _sendInvite() async {
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione um usuário para convidar'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final controller = context.read<AppointmentController>();
      final success = await controller.createInvite(
        appointmentId: widget.appointmentId,
        invitedUserId: _selectedUserId!,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Convite enviado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.error ?? 'Erro ao enviar convite'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person_add,
                      color: AppColors.primary.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Convidar Usuário',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.appointmentTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Busca de usuários
                    CustomTextField(
                      label: 'Buscar usuário',
                      controller: _searchController,
                      prefixIcon: const Icon(Icons.search),
                      onChanged: (value) {
                        // TODO: Implementar busca
                      },
                    ),
                    const SizedBox(height: 16),
                    // Lista de usuários
                    if (_isLoadingUsers)
                      const Center(child: CircularProgressIndicator())
                    else if (_users.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Nenhum usuário encontrado',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: ThemeHelpers.borderColor(context),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            final isSelected = _selectedUserId == user['id'];
                            return ListTile(
                              selected: isSelected,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.primary,
                                child: Text(
                                  (user['name'] as String? ?? 'U')[0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(user['name'] ?? ''),
                              subtitle: Text(user['email'] ?? ''),
                              onTap: () {
                                setState(() {
                                  _selectedUserId = user['id'];
                                });
                              },
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: AppColors.primary.primary,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Mensagem opcional
                    CustomTextField(
                      label: 'Mensagem (opcional)',
                      controller: _messageController,
                      maxLines: 3,
                      hint: 'Adicione uma mensagem personalizada ao convite',
                    ),
                    const SizedBox(height: 24),
                    // Botões
                    CustomButton(
                      text: 'Enviar Convite',
                      icon: Icons.send,
                      onPressed: _isLoading ? null : _sendInvite,
                      isLoading: _isLoading,
                      isFullWidth: true,
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      text: 'Cancelar',
                      variant: ButtonVariant.secondary,
                      icon: Icons.close,
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      isFullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

