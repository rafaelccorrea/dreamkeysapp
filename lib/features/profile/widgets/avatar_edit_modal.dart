import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/utils/image_crop_helper.dart';

/// Modal **flush** de edição de foto de perfil.
///
/// Paleta coerente e com significado (sem rainbow):
///   • **primary** (marca) — anel do avatar, badge de câmera e CTA de salvar.
///   • **info/azul** — painel de dicas/especificações (informativo).
///   • **success/verde** — confirmação de imagem selecionada.
///   • **error/vermelho** — apenas a ação destrutiva de remover.
///
/// O `onSave` retorna `Future<bool>`: o modal aguarda, mostra progresso e só
/// fecha em sucesso (em erro permanece aberto para nova tentativa).
class AvatarEditModal {
  static Future<void> show({
    required BuildContext context,
    required Future<bool> Function(String? avatarPath) onSave,
    String? currentAvatar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) =>
          _AvatarEditModalContent(onSave: onSave, currentAvatar: currentAvatar),
    );
  }
}

class _AvatarEditModalContent extends StatefulWidget {
  final Future<bool> Function(String? avatarPath) onSave;
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
  bool _isRemoving = false;

  bool get _busy => _isUploading || _isRemoving;

  Color _primary(bool isDark) =>
      isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  Color _info(bool isDark) =>
      isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
  Color _success(bool isDark) =>
      isDark ? AppColors.status.successDarkMode : AppColors.status.success;
  Color _danger(bool isDark) =>
      isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        _snack('Arquivo muito grande. Máximo: 5MB', _danger(_isDark));
        return;
      }

      if (!mounted) return;
      try {
        final croppedFile = await ImageCropHelper.cropImageCircle(
          imagePath: file.path,
          compressQuality: 85,
        );
        if (!mounted) return;
        setState(() => _selectedImage = croppedFile ?? file);
      } catch (cropError) {
        if (!mounted) return;
        setState(() => _selectedImage = file);
        _snack('Recorte indisponível. Usando imagem original.',
            _info(_isDark));
      }
    } catch (e) {
      if (mounted) _snack('Erro ao selecionar imagem', _danger(_isDark));
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleUpload() async {
    if (_selectedImage == null || _busy) return;
    setState(() => _isUploading = true);
    final ok = await widget.onSave(_selectedImage!.path);
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _handleRemove() async {
    if (_busy) return;
    setState(() => _isRemoving = true);
    final ok = await widget.onSave(null);
    if (!mounted) return;
    setState(() => _isRemoving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = _primary(isDark);
    final hasCurrent =
        widget.currentAvatar != null && widget.currentAvatar!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      primary.withValues(alpha: 0.55),
                      primary.withValues(alpha: 0.28),
                    ]),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: _buildHeader(context, theme, isDark, primary),
              ),
              const SizedBox(height: 22),
              _buildPreview(context, isDark, primary),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSourceButtons(context, theme, isDark, primary),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTipPanel(context, theme, isDark),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _buildActions(context, theme, isDark, primary, hasCurrent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: isDark ? 0.42 : 0.22),
                primary.withValues(alpha: isDark ? 0.22 : 0.12),
              ],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.photo_camera_rounded, color: primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Foto de perfil',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(context),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Escolha de onde quer enviar sua nova foto.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        _CircleClose(onTap: _busy ? null : () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, bool isDark, Color primary) {
    final success = _success(isDark);
    final hasSelected = _selectedImage != null;
    final ringColor = hasSelected ? success : primary;
    const size = 132.0;

    Widget inner;
    if (hasSelected) {
      inner = Image.file(_selectedImage!, fit: BoxFit.cover);
    } else if (widget.currentAvatar != null &&
        widget.currentAvatar!.isNotEmpty) {
      inner = Image.network(
        widget.currentAvatar!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _previewFallback(context, isDark),
      );
    } else {
      inner = _previewFallback(context, isDark);
    }

    return Center(
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Halo suave atrás do avatar.
            Container(
              width: size + 10,
              height: size + 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ringColor.withValues(alpha: isDark ? 0.22 : 0.14),
                    ringColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border.all(
                  color: ringColor.withValues(alpha: isDark ? 0.6 : 0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ringColor.withValues(alpha: isDark ? 0.28 : 0.16),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: inner,
            ),
            // Badge inferior — verde (selecionado) ou primary (câmera).
            Positioned(
              bottom: 4,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringColor,
                  border: Border.all(
                    color: ThemeHelpers.cardBackgroundColor(context),
                    width: 3,
                  ),
                ),
                child: Icon(
                  hasSelected
                      ? Icons.check_rounded
                      : Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewFallback(BuildContext context, bool isDark) {
    return Container(
      color: isDark
          ? AppColors.background.backgroundSecondaryDarkMode
          : AppColors.background.backgroundSecondary,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: 64,
        color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildSourceButtons(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
  ) {
    return Row(
      children: [
        Expanded(
          child: _SourceTile(
            icon: Icons.photo_camera_rounded,
            label: 'Câmera',
            tone: primary,
            enabled: !_busy,
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SourceTile(
            icon: Icons.photo_library_rounded,
            label: 'Galeria',
            tone: primary,
            enabled: !_busy,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  Widget _buildTipPanel(BuildContext context, ThemeData theme, bool isDark) {
    final info = _info(isDark);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: info.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: info.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: info),
              const SizedBox(width: 8),
              Text(
                'Para uma foto nítida',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: info,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _tipRow(context, theme, Icons.crop_rounded,
              'Quadrada (1:1), ideal 400×400px'),
          const SizedBox(height: 6),
          _tipRow(context, theme, Icons.image_outlined,
              'JPG, PNG, GIF ou WebP'),
          const SizedBox(height: 6),
          _tipRow(context, theme, Icons.storage_rounded,
              'Até 5MB por imagem'),
        ],
      ),
    );
  }

  Widget _tipRow(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String text,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
    bool hasCurrent,
  ) {
    final danger = _danger(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // CTA primário — habilitado só quando há nova imagem selecionada.
        FilledButton.icon(
          onPressed:
              (_selectedImage == null || _busy) ? null : _handleUpload,
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: primary.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
          ),
          icon: _isUploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_rounded, size: 19),
          label: Text(_isUploading ? 'Enviando…' : 'Salvar foto'),
        ),
        if (hasCurrent) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _handleRemove,
            style: OutlinedButton.styleFrom(
              foregroundColor: danger,
              side: BorderSide(color: danger.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            icon: _isRemoving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: danger,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(_isRemoving ? 'Removendo…' : 'Remover foto atual'),
          ),
        ],
      ],
    );
  }
}

/// Tile de origem (Câmera/Galeria) — flush, com ícone tonal e label.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.tone,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: tone.withValues(alpha: 0.12),
          highlightColor: tone.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              color: tone.withValues(alpha: isDark ? 0.1 : 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tone.withValues(alpha: isDark ? 0.32 : 0.22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: tone, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão circular de fechar — coerente com o resto dos sheets refinados.
class _CircleClose extends StatelessWidget {
  const _CircleClose({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: secondary.withValues(alpha: isDark ? 0.14 : 0.08),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          child: Icon(Icons.close_rounded, size: 19, color: secondary),
        ),
      ),
    );
  }
}
