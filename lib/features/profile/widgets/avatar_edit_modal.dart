import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Modal para edição de avatar
class AvatarEditModal {
  static void show({
    required BuildContext context,
    required Function(String? avatarUrl) onSave,
    String? currentAvatar,
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
      builder: (context) =>
          _AvatarEditModalContent(onSave: onSave, currentAvatar: currentAvatar),
    );
  }
}

class _AvatarEditModalContent extends StatefulWidget {
  final Function(String? avatarUrl) onSave;
  final String? currentAvatar;

  const _AvatarEditModalContent({required this.onSave, this.currentAvatar});

  @override
  State<_AvatarEditModalContent> createState() =>
      _AvatarEditModalContentState();
}

class _AvatarEditModalContentState extends State<_AvatarEditModalContent> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isUploading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final fileSize = await file.length();

        // Validar tamanho (5MB)
        if (fileSize > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Arquivo muito grande. Tamanho máximo: 5MB',
                ),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedImage = file;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione uma imagem primeiro'),
          backgroundColor: AppColors.status.warning,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Passar o caminho do arquivo para o callback
      widget.onSave(_selectedImage!.path);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.primary.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Alterar Foto de Perfil',
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

              // Preview do avatar atual
              Center(
                child: Container(
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
                    child: _selectedImage != null
                        ? Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: isDark
                                    ? AppColors
                                          .background
                                          .backgroundSecondaryDarkMode
                                    : AppColors.background.backgroundSecondary,
                                child: Icon(
                                  Icons.person,
                                  size: 60,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              );
                            },
                          )
                        : widget.currentAvatar != null &&
                              widget.currentAvatar!.isNotEmpty
                        ? Image.network(
                            widget.currentAvatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: isDark
                                    ? AppColors
                                          .background
                                          .backgroundSecondaryDarkMode
                                    : AppColors.background.backgroundSecondary,
                                child: Icon(
                                  Icons.person,
                                  size: 60,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: isDark
                                ? AppColors
                                      .background
                                      .backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                            child: Icon(
                              Icons.person,
                              size: 60,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Informações
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.primary.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Especificações',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSpecItem(
                      theme,
                      context,
                      Icons.image_outlined,
                      'Formatos aceitos: JPG, PNG, GIF, WebP',
                    ),
                    const SizedBox(height: 8),
                    _buildSpecItem(
                      theme,
                      context,
                      Icons.storage_outlined,
                      'Tamanho máximo: 5MB',
                    ),
                    const SizedBox(height: 8),
                    _buildSpecItem(
                      theme,
                      context,
                      Icons.aspect_ratio_outlined,
                      'Dimensões recomendadas: 400x400px',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botões
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isUploading
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Câmera'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isUploading
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Galeria'),
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
                  if (_selectedImage != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _handleUpload,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.upload_file),
                        label: Text(
                          _isUploading ? 'Enviando...' : 'Enviar Imagem',
                        ),
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
                  ],
                  if (widget.currentAvatar != null &&
                      widget.currentAvatar!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          widget.onSave(null);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remover Avatar'),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
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
    );
  }

  Widget _buildSpecItem(
    ThemeData theme,
    BuildContext context,
    IconData icon,
    String text,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
