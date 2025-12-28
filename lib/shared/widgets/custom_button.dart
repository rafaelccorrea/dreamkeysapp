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
        : (this.width ?? (isFullWidth ? double.infinity : null));

    final buttonStyle = _getButtonStyle(context, variant);

    Widget content = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == ButtonVariant.primary
                    ? theme.colorScheme.onPrimary
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

    final buttonWidget = switch (variant) {
      ButtonVariant.primary => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: buttonStyle,
          child: content,
        ),
      ButtonVariant.secondary => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: buttonStyle,
          child: content,
        ),
      ButtonVariant.text => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: buttonStyle,
          child: content,
        ),
    };

    if (width != null) {
      return SizedBox(
        width: width,
        child: buttonWidget,
      );
    }
    return buttonWidget;
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
