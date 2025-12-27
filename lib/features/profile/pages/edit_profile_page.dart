import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/tag_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/custom_button.dart';

/// Página de edição de perfil
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  Profile? _profile;
  List<Tag> _availableTags = [];
  List<String> _selectedTagIds = [];
  bool _isLoading = true;
  bool _isLoadingTags = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadTags();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
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
            _nameController.text = _profile!.name;
            _phoneController.text = _profile!.phone ?? _profile!.cellphone ?? '';
            _selectedTagIds = _profile!.tagIds?.toList() ?? [];
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

  Future<void> _loadTags() async {
    setState(() {
      _isLoadingTags = true;
    });

    try {
      final response = await TagService.instance.getTags();

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _availableTags = response.data!;
            _isLoadingTags = false;
          });
        } else {
          setState(() {
            _isLoadingTags = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ProfileService.instance.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        tagIds: _selectedTagIds.isNotEmpty ? _selectedTagIds : null,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Perfil atualizado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar perfil'),
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
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Editar Perfil',
      currentBottomNavIndex: -1,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null
              ? _buildErrorState(context, theme)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
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
                        const SizedBox(height: 24),
                        CustomTextField(
                          controller: _nameController,
                          label: 'Nome Completo *',
                          prefixIcon: Icon(Icons.person_outline),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Nome é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          controller: _phoneController,
                          label: 'Telefone',
                          prefixIcon: Icon(Icons.phone_outlined),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Tags',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTagsSelector(context, theme),
                        const SizedBox(height: 32),
                        CustomButton(
                          text: _isSaving ? 'Salvando...' : 'Salvar Alterações',
                          onPressed: _isSaving ? null : _handleSave,
                          icon: _isSaving ? null : Icons.save,
                          isLoading: _isSaving,
                        ),
                        const SizedBox(height: 12),
                        CustomButton(
                          text: 'Cancelar',
                          onPressed: () => Navigator.pop(context),
                          icon: Icons.close,
                          variant: ButtonVariant.secondary,
                        ),
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
          SkeletonBox(width: double.infinity, height: 60),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 60),
          const SizedBox(height: 32),
          SkeletonBox(width: double.infinity, height: 50),
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

  Widget _buildTagsSelector(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoadingTags) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_availableTags.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.background.backgroundSecondaryDarkMode
              : AppColors.background.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nenhuma tag disponível',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundSecondaryDarkMode
            : AppColors.background.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _availableTags.map((tag) {
          final isSelected = _selectedTagIds.contains(tag.id);
          return FilterChip(
            label: Text(tag.name),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedTagIds.add(tag.id);
                } else {
                  _selectedTagIds.remove(tag.id);
                }
              });
            },
            selectedColor: AppColors.primary.primary.withOpacity(0.2),
            checkmarkColor: AppColors.primary.primary,
            labelStyle: TextStyle(
              color: isSelected
                  ? AppColors.primary.primary
                  : ThemeHelpers.textColor(context),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            avatar: isSelected
                ? Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppColors.primary.primary,
                  )
                : null,
          );
        }).toList(),
      ),
    );
  }
}

