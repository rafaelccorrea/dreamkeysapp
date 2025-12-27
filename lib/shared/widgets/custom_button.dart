import 'package:flutter/material.dart';

/// Botão customizado com variantes
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final ButtonVariant variant;
  final double? width;
  final IconData? icon;
  final bool isFullWidth;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = ButtonVariant.primary,
    this.width,
    this.icon,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = isFullWidth
        ? MediaQuery.of(context).size.width
        : (this.width ?? double.infinity);

    final buttonStyle = _getButtonStyle(context, variant);

    Widget content = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == ButtonVariant.primary
                    ? Colors.white
                    : theme.colorScheme.primary,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(text),
            ],
          );

    switch (variant) {
      case ButtonVariant.primary:
        return SizedBox(
          width: width,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: buttonStyle,
            child: content,
          ),
        );
      case ButtonVariant.secondary:
        return SizedBox(
          width: width,
          child: OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: buttonStyle,
            child: content,
          ),
        );
      case ButtonVariant.text:
        return SizedBox(
          width: width,
          child: TextButton(
            onPressed: isLoading ? null : onPressed,
            style: buttonStyle,
            child: content,
          ),
        );
    }
  }

  ButtonStyle? _getButtonStyle(BuildContext context, ButtonVariant variant) {
    final theme = Theme.of(context);
    final baseStyle = theme.elevatedButtonTheme.style?.copyWith(
      minimumSize: WidgetStateProperty.all(const Size(0, 48)),
    );

    switch (variant) {
      case ButtonVariant.primary:
        return baseStyle;
      case ButtonVariant.secondary:
        return theme.outlinedButtonTheme.style?.copyWith(
          minimumSize: WidgetStateProperty.all(const Size(0, 48)),
        );
      case ButtonVariant.text:
        return theme.textButtonTheme.style?.copyWith(
          minimumSize: WidgetStateProperty.all(const Size(0, 48)),
        );
    }
  }
}

enum ButtonVariant {
  primary,
  secondary,
  text,
}
