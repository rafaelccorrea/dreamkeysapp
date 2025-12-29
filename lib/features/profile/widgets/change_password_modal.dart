import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';

/// Modal para alteração de senha
class ChangePasswordModal {
  static void show({
    required BuildContext context,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => const _ChangePasswordModalContent(),
    );
  }
}

class _ChangePasswordModalContent extends StatefulWidget {
  const _ChangePasswordModalContent();

  @override
  State<_ChangePasswordModalContent> createState() => _ChangePasswordModalContentState();
}

class _ChangePasswordModalContentState extends State<_ChangePasswordModalContent> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ProfileService.instance.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Senha alterada com sucesso! Todas as outras sessões foram desconectadas.'),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao alterar senha'),
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
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: AppColors.primary.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Alterar Senha',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
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
                const SizedBox(height: 24),

                // Senha atual
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Senha Atual *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Senha atual é obrigatória';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Nova senha
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'Nova Senha *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nova senha é obrigatória';
                    }
                    if (value.length < 6) {
                      return 'Nova senha deve ter pelo menos 6 caracteres';
                    }
                    if (value == _currentPasswordController.text) {
                      return 'A nova senha deve ser diferente da senha atual';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirmar senha
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Nova Senha *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirmação de senha é obrigatória';
                    }
                    if (value != _newPasswordController.text) {
                      return 'As senhas não coincidem';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Botões
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleSubmit,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Alterando...' : 'Alterar Senha'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





