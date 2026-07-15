import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// Campo de texto do onboarding — mesma gramática visual dos campos do
/// login (filled, cantos 14, ícone prefixo em "caixinha" que acende com o
/// foco, label flutuante no accent).
class OnboardingTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool enabled;
  final String? hint;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;

  const OnboardingTextField({
    super.key,
    required this.controller,
    required this.label,
    this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.inputFormatters,
    this.maxLength,
    this.enabled = true,
    this.hint,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
  });

  @override
  State<OnboardingTextField> createState() => _OnboardingTextFieldState();
}

class _OnboardingTextFieldState extends State<OnboardingTextField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final fillColor = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : const Color(0xFFF6F7FB);
    final borderColor = isDark
        ? AppColors.border.borderDarkMode.withValues(alpha: 0.9)
        : AppColors.border.border;
    final labelMuted =
        isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;

    Widget? prefix;
    if (widget.prefixIcon != null) {
      final isFocused = _focusNode.hasFocus;
      prefix = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isFocused
                ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
                : (isDark
                    ? AppColors.background.backgroundDarkMode
                        .withValues(alpha: 0.5)
                    : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFocused
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.35)
                  : borderColor.withValues(alpha: isDark ? 0.6 : 0.8),
              width: 1,
            ),
          ),
          child: Icon(
            widget.prefixIcon,
            size: 18,
            color: isFocused ? accent : labelMuted,
          ),
        ),
      );
    }

    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      autovalidateMode: widget.autovalidateMode,
      textInputAction: widget.textInputAction ??
          (widget.onSubmitted != null
              ? TextInputAction.next
              : TextInputAction.done),
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.text.textDarkMode : AppColors.text.text,
        height: 1.25,
      ),
      cursorColor: accent,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(2),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        hintText: widget.hint,
        hintStyle: GoogleFonts.poppins(
          color: labelMuted.withValues(alpha: 0.75),
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
        ),
        counterText: '',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: GoogleFonts.poppins(
          color: labelMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: GoogleFonts.poppins(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 56,
          minHeight: 36,
        ),
        suffixIcon: widget.suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 40,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.status.error.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.status.error, width: 1.25),
        ),
        errorStyle: GoogleFonts.poppins(
          color: AppColors.status.error,
          fontSize: 11,
          height: 1.2,
        ),
        errorMaxLines: 2,
        filled: true,
        fillColor: widget.enabled
            ? fillColor
            : fillColor.withValues(alpha: 0.55),
        contentPadding: EdgeInsets.fromLTRB(
          widget.prefixIcon != null ? 4 : 16,
          18,
          12,
          18,
        ),
      ),
      validator: widget.validator,
    );
  }
}
