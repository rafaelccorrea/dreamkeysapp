import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';
import '../widgets/sessions_modal.dart';

/// Página principal de perfil do usuário
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUpdatingVisibility = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ProfileService.instance.getProfile();

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _profile = response.data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar perfil';
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

  Future<void> _handleAvatarChange(String? avatarUrlOrPath) async {
    if (avatarUrlOrPath == null) {
      // Remover avatar
      final response = await ProfileService.instance.removeAvatar();
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _profile = response.data;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Avatar removido com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao remover avatar'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } else {
      // Upload de avatar (avatarUrlOrPath é o caminho do arquivo)
      final imageFile = File(avatarUrlOrPath);
      if (!await imageFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Arquivo não encontrado'),
            backgroundColor: AppColors.status.error,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final response = await ProfileService.instance.uploadAvatar(imageFile);
        
        if (mounted) {
          if (response.success && response.data != null) {
            // Recarregar perfil para obter o avatar atualizado
            await _loadProfile();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Avatar atualizado com sucesso!'),
                backgroundColor: AppColors.status.success,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao fazer upload do avatar'),
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
  }

  Future<void> _togglePublicVisibility() async {
    if (_profile == null) return;

    setState(() {
      _isUpdatingVisibility = true;
    });

    try {
      final response = await ProfileService.instance.updatePublicVisibility(
        !_profile!.isAvailableForPublicSite,
      );

      if (mounted) {
        if (response.success) {
          final newVisibility = response.data ?? _profile!.isAvailableForPublicSite;
          setState(() {
            _profile = Profile(
              id: _profile!.id,
              name: _profile!.name,
              email: _profile!.email,
              phone: _profile!.phone,
              cellphone: _profile!.cellphone,
              avatar: _profile!.avatar,
              role: _profile!.role,
              companyId: _profile!.companyId,
              companyName: _profile!.companyName,
              isAvailableForPublicSite: newVisibility,
              preferences: _profile!.preferences,
              createdAt: _profile!.createdAt,
              updatedAt: _profile!.updatedAt,
            );
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar visibilidade'),
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
          _isUpdatingVisibility = false;
        });
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Administrador';
      case 'master':
        return 'Master';
      case 'manager':
        return 'Gerente';
      case 'user':
      default:
        return 'Usuário';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Meu Perfil',
      currentBottomNavIndex: -1,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadProfile,
          tooltip: 'Atualizar',
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null
              ? _buildErrorState(context, theme)
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar e informações básicas
                        _buildHeader(context, theme, isDark),
                        const SizedBox(height: 32),

                        // Informações pessoais
                        _buildPersonalInfo(context, theme, isDark),
                        const SizedBox(height: 32),

                        // Segurança
                        _buildSecuritySection(context, theme, isDark),
                        const SizedBox(height: 32),

                        // Visibilidade pública
                        _buildPublicVisibilitySection(context, theme, isDark),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SkeletonBox(
            width: 120,
            height: 120,
            borderRadius: 60,
          ),
          const SizedBox(height: 24),
          SkeletonBox(width: double.infinity, height: 200),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 150),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
              'Erro ao carregar perfil',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              AvatarEditModal.show(
                context: context,
                onSave: _handleAvatarChange,
                currentAvatar: _profile?.avatar,
              );
            },
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.primary,
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: _profile?.avatar != null && _profile!.avatar!.isNotEmpty
                        ? Image.network(
                            _profile!.avatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: isDark
                                    ? AppColors.background.backgroundSecondaryDarkMode
                                    : AppColors.background.backgroundSecondary,
                                child: Icon(
                                  Icons.person,
                                  size: 60,
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: isDark
                                ? AppColors.background.backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                            child: Icon(
                              Icons.person,
                              size: 60,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _profile?.name ?? '',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _profile?.email ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.profileEdit);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Editar Perfil'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfo(BuildContext context, ThemeData theme, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informações Pessoais',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 20),
            _buildInfoRow(
              theme,
              context,
              Icons.person_outline,
              'Nome',
              _profile?.name ?? '',
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              context,
              Icons.email_outlined,
              'Email',
              _profile?.email ?? '',
            ),
            if (_profile?.phone != null || _profile?.cellphone != null) ...[
              const SizedBox(height: 16),
              _buildInfoRow(
                theme,
                context,
                Icons.phone_outlined,
                'Telefone',
                _profile?.phone ?? _profile?.cellphone ?? '',
              ),
            ],
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              context,
              Icons.badge_outlined,
              'Cargo',
              _getRoleLabel(_profile?.role ?? 'user'),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              context,
              Icons.calendar_today_outlined,
              'Membro desde',
              _formatDate(_profile?.createdAt ?? ''),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context, ThemeData theme, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Segurança',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                Icons.devices_outlined,
                color: AppColors.primary.primary,
              ),
              title: Text(
                'Sessões Ativas',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              subtitle: Text(
                'Gerencie suas sessões ativas',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                SessionsModal.show(context: context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.lock_outline,
                color: AppColors.primary.primary,
              ),
              title: Text(
                'Alterar Senha',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              subtitle: Text(
                'Altere sua senha de acesso',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ChangePasswordModal.show(context: context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicVisibilitySection(BuildContext context, ThemeData theme, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.public_outlined,
              color: AppColors.primary.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visibilidade Pública',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aparecer na lista de corretores do site público',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (_isUpdatingVisibility)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: _profile?.isAvailableForPublicSite ?? false,
                onChanged: (_) => _togglePublicVisibility(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

