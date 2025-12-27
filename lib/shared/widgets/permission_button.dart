import 'package:flutter/material.dart';
import '../services/module_access_service.dart';
import '../../core/theme/app_colors.dart';

/// Botão que se desabilita automaticamente se não tem permissão
/// Similar ao PermissionButton do React
class PermissionButton extends StatelessWidget {
  final String permission;
  final VoidCallback? onPressed;
  final Widget child;
  final bool disabled;
  final ButtonStyle? style;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final OutlinedBorder? shape;

  const PermissionButton({
    super.key,
    required this.permission,
    this.onPressed,
    required this.child,
    this.disabled = false,
    this.style,
    this.tooltip,
    this.padding,
    this.minimumSize,
    this.backgroundColor,
    this.foregroundColor,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    final hasPermission = moduleAccess.hasPermission(permission);
    final isDisabled = disabled || !hasPermission;

    final defaultTooltip = !hasPermission
        ? 'Você não tem permissão para esta ação. Entre em contato com um administrador.'
        : tooltip;

    Widget button = ElevatedButton(
      onPressed: isDisabled ? null : onPressed,
      style: style ??
          ElevatedButton.styleFrom(
            backgroundColor: backgroundColor ?? AppColors.primary.primary,
            foregroundColor: foregroundColor ?? Colors.white,
            padding: padding,
            minimumSize: minimumSize,
            shape: shape ??
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
            disabledBackgroundColor: AppColors.background.backgroundSecondary,
            disabledForegroundColor: AppColors.text.textSecondary,
          ),
      child: child,
    );

    if (defaultTooltip != null && isDisabled) {
      return Tooltip(
        message: defaultTooltip,
        child: button,
      );
    }

    return button;
  }
}

