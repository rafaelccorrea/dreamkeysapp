import 'package:flutter/material.dart';
import '../services/module_access_service.dart';
import '../../core/theme/app_colors.dart';

/// Item de menu que se desabilita ou oculta se não tem permissão
/// Similar ao PermissionMenuItem do React
class PermissionMenuItem extends StatelessWidget {
  final String permission;
  final VoidCallback? onTap;
  final Widget child;
  final bool danger;
  final bool disabled;
  final bool hideIfNoPermission;
  final EdgeInsetsGeometry? padding;

  const PermissionMenuItem({
    super.key,
    required this.permission,
    this.onTap,
    required this.child,
    this.danger = false,
    this.disabled = false,
    this.hideIfNoPermission = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    final hasPermission = moduleAccess.hasPermission(permission);
    final isDisabled = disabled || !hasPermission;

    if (!hasPermission && hideIfNoPermission) {
      return const SizedBox.shrink();
    }

    final color = danger
        ? AppColors.status.error
        : (isDisabled
            ? AppColors.text.textSecondary
            : AppColors.text.text);

    Widget content = child;
    
    if (isDisabled && !hasPermission) {
      content = Tooltip(
        message: 'Você não tem permissão para esta ação. Entre em contato com um administrador.',
        child: DefaultTextStyle(
          style: TextStyle(color: color),
          child: child,
        ),
      );
    }

    return ListTile(
      onTap: isDisabled ? null : onTap,
      enabled: !isDisabled,
      contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      textColor: color,
      iconColor: color,
      title: content,
    );
  }
}

