import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/utils/image_crop_helper.dart';

/// Modal **flush** de edição de foto de perfil — calmo e coerente (NÃO vermelho).
///
/// Acento **índigo** (mesmo DNA editorial da tela de Usuários) para avatar,
/// origem e CTA; **verde** confirma a imagem selecionada; **vermelho** só na
/// ação destrutiva de remover. Feedback de seleção fica inline (sem snackbar
/// atrás do sheet); o resultado do upload é avisado pela página após fechar.
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
  String? _inlineError;

  bool get _busy => _isUploading || _isRemoving;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // Acento calmo (índigo) — coerente com as telas editoriais do app.
  Color get _accent =>
      _isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  Color get _success =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;
  Color get _danger =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _inlineError = null);
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 8 * 1024 * 1024) {
        if (mounted) {
          setState(() => _inlineError = 'Imagem muito grande (máx. 8MB).');
        }
        return;
      }

      if (!mounted) return;
      try {
        final croppedFile = await ImageCropHelper.cropImageCircle(
          imagePath: file.path,
          compressQuality: 88,
        );
        if (!mounted) return;
        setState(() => _selectedImage = croppedFile ?? file);
      } catch (_) {
        // Recorte indisponível para o formato — segue com a imagem original.
        if (!mounted) return;
        setState(() => _selectedImage = file);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _inlineError = 'Não foi possível abrir essa imagem.');
      }
    }
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
    final accent = _accent;
    final hasCurrent =
        widget.currentAvatar != null && widget.currentAvatar!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
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
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: _buildHeader(context, theme, isDark, accent),
              ),
              const SizedBox(height: 20),
              _buildPreview(context, isDark, accent),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSourceButtons(context, theme, isDark, accent),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTip(context, theme, isDark, accent),
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildInlineError(context, theme),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _buildActions(context, theme, isDark, accent, hasCurrent),
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
    Color accent,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Icon(Icons.photo_camera_rounded, color: accent, size: 19),
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
                'Escolha de onde enviar sua nova foto.',
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

  Widget _buildPreview(BuildContext context, bool isDark, Color accent) {
    final hasSelected = _selectedImage != null;
    final ring = hasSelected ? _success : accent;
    const size = 124.0;

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
        width: size + 14,
        height: size + 14,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border.all(
                  color: ring.withValues(alpha: isDark ? 0.55 : 0.38),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ring.withValues(alpha: isDark ? 0.22 : 0.12),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: inner,
            ),
            Positioned(
              bottom: 2,
              right: 14,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ring,
                  border: Border.all(
                    color: ThemeHelpers.cardBackgroundColor(context),
                    width: 3,
                  ),
                ),
                child: Icon(
                  hasSelected ? Icons.check_rounded : Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 15,
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
        size: 58,
        color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildSourceButtons(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accent,
  ) {
    return Row(
      children: [
        Expanded(
          child: _SourceButton(
            icon: Icons.photo_camera_rounded,
            label: 'Câmera',
            tone: accent,
            enabled: !_busy,
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SourceButton(
            icon: Icons.photo_library_rounded,
            label: 'Galeria',
            tone: accent,
            enabled: !_busy,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  Widget _buildTip(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accent,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: secondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Foto quadrada e nítida fica melhor · JPG, PNG, HEIC ou WebP · até 8MB',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineError(BuildContext context, ThemeData theme) {
    final danger = _danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _inlineError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: danger,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accent,
    bool hasCurrent,
  ) {
    final danger = _danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: (_selectedImage == null || _busy) ? null : _handleUpload,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: accent.withValues(alpha: 0.35),
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
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _handleRemove,
            style: TextButton.styleFrom(
              foregroundColor: danger,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            icon: _isRemoving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: danger,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(_isRemoving ? 'Removendo…' : 'Remover foto atual'),
          ),
        ],
      ],
    );
  }
}

/// Botão de origem (Câmera/Galeria) — compacto e calmo: fundo neutro do card,
/// borda sutil e ícone/rótulo no tom de acento. Nada de fill agressivo.
class _SourceButton extends StatelessWidget {
  const _SourceButton({
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
          borderRadius: BorderRadius.circular(13),
          splashColor: tone.withValues(alpha: 0.12),
          highlightColor: tone.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundTertiaryDarkMode
                  : AppColors.background.backgroundTertiary,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: tone, size: 19),
                  const SizedBox(width: 8),
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

/// Botão circular de fechar — coerente com os demais sheets refinados.
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
