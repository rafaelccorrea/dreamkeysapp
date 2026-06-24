import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';

/// Modal **flush** de alteração de senha.
///
/// Detalhes ricos e coerentes:
///   • Cabeçalho com plate tonal (primary) + título/subtítulo + fechar circular.
///   • **Medidor de força** semântico (vermelho → âmbar → verde).
///   • **Checklist de requisitos** com checks verdes em tempo real.
class ChangePasswordModal {
  static Future<void> show({required BuildContext context}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const _ChangePasswordModalContent(),
    );
  }
}

class _ChangePasswordModalContent extends StatefulWidget {
  const _ChangePasswordModalContent();

  @override
  State<_ChangePasswordModalContent> createState() =>
      _ChangePasswordModalContentState();
}

class _ChangePasswordModalContentState
    extends State<_ChangePasswordModalContent> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_onChanged);
    _confirmPasswordController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ─── Força da senha ────────────────────────────────────────────────────
  // 0 = vazia · 1 = fraca · 2 = média · 3 = forte
  int get _strength {
    final p = _newPasswordController.text;
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (score <= 1) return 1;
    if (score <= 3) return 2;
    return 3;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await ProfileService.instance.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Senha alterada! As outras sessões foram desconectadas.',
            ),
            backgroundColor: AppColors.status.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        _snack(response.message ?? 'Erro ao alterar senha',
            AppColors.status.error);
      }
    } catch (e) {
      if (mounted) _snack('Erro: ${e.toString()}', AppColors.status.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 16),
                  _buildHeader(context, theme, isDark, primary),
                  const SizedBox(height: 22),
                  _PasswordField(
                    controller: _currentPasswordController,
                    label: 'Senha atual',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscureCurrent,
                    onToggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                    tone: primary,
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Informe sua senha atual'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _newPasswordController,
                    label: 'Nova senha',
                    icon: Icons.lock_reset_rounded,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    tone: primary,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Informe a nova senha';
                      if (v.length < 6) return 'Mínimo de 6 caracteres';
                      if (v == _currentPasswordController.text) {
                        return 'A nova senha deve ser diferente da atual';
                      }
                      return null;
                    },
                  ),
                  if (_newPasswordController.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StrengthMeter(strength: _strength),
                    const SizedBox(height: 12),
                    _buildChecklist(context, theme, isDark),
                  ],
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _confirmPasswordController,
                    label: 'Confirmar nova senha',
                    icon: Icons.check_circle_outline_rounded,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    tone: primary,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Confirme a nova senha';
                      if (v != _newPasswordController.text) {
                        return 'As senhas não coincidem';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: primary.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14.5),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.shield_rounded, size: 19),
                    label: Text(_isLoading ? 'Alterando…' : 'Alterar senha'),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
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
          child: Icon(Icons.lock_rounded, color: primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alterar senha',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(context),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Por segurança, as outras sessões serão desconectadas.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        _CircleClose(onTap: _isLoading ? null : () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildChecklist(BuildContext context, ThemeData theme, bool isDark) {
    final p = _newPasswordController.text;
    final reqLen = p.length >= 6;
    final reqDiff =
        p.isNotEmpty && p != _currentPasswordController.text;
    final reqMatch = p.isNotEmpty && p == _confirmPasswordController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChecklistItem(ok: reqLen, label: 'Pelo menos 6 caracteres'),
        const SizedBox(height: 5),
        _ChecklistItem(ok: reqDiff, label: 'Diferente da senha atual'),
        const SizedBox(height: 5),
        _ChecklistItem(ok: reqMatch, label: 'Confirmação coincide'),
      ],
    );
  }
}

/// Campo de senha refinado, com toggle de visibilidade e foco tonal.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.obscure,
    required this.onToggle,
    required this.tone,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final VoidCallback onToggle;
  final Color tone;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w600,
      ),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: fill,
        prefixIcon: Icon(icon, size: 20, color: tone),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onPressed: onToggle,
        ),
        border: border(ThemeHelpers.borderLightColor(context), 1),
        enabledBorder: border(ThemeHelpers.borderLightColor(context), 1),
        focusedBorder: border(tone.withValues(alpha: isDark ? 0.6 : 0.45), 1.5),
        errorBorder: border(AppColors.status.error, 1.2),
        focusedErrorBorder: border(AppColors.status.error, 1.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}

/// Medidor de força — barra segmentada com cor semântica e rótulo.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});
  final int strength; // 1..3

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final track = ThemeHelpers.borderLightColor(context);

    final (Color color, String label) = switch (strength) {
      1 => (
          isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
          'Fraca'
        ),
      2 => (
          isDark ? AppColors.status.warningDarkMode : AppColors.status.warning,
          'Média'
        ),
      _ => (
          isDark ? AppColors.status.successDarkMode : AppColors.status.success,
          'Forte'
        ),
    };

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              final filled = i < strength;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 5,
                  decoration: BoxDecoration(
                    color: filled ? color : track,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

/// Item de checklist — check verde quando cumprido, neutro quando não.
class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.ok, required this.label});
  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final color = ok ? success : neutral;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ok ? ThemeHelpers.textColor(context) : neutral,
            fontWeight: ok ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
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
