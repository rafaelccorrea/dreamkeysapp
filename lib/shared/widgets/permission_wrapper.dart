import 'package:flutter/material.dart';
import '../services/module_access_service.dart';

/// Widget que controla renderização baseado em permissões e módulos
/// Similar ao PermissionWrapper do React
class PermissionWrapper extends StatelessWidget {
  final Widget child;
  final String? permission;
  final List<String>? permissions;
  final bool requireAll;
  final String? moduleId;
  final Widget? fallback;
  final bool hideIfNoPermission;

  const PermissionWrapper({
    super.key,
    required this.child,
    this.permission,
    this.permissions,
    this.requireAll = false,
    this.moduleId,
    this.fallback,
    this.hideIfNoPermission = true,
  }) : assert(
          permission != null || permissions != null || moduleId != null,
          'Deve fornecer permission, permissions ou moduleId',
        );

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    bool hasAccess = true;

    // Verificar módulo primeiro (se especificado)
    if (moduleId != null) {
      hasAccess = moduleAccess.isModuleAvailableForCompany(moduleId!) &&
          moduleAccess.hasPermissionForModule(moduleId!);
    }

    // Se módulo passou ou não foi especificado, verificar permissões
    if (hasAccess) {
      if (permission != null) {
        hasAccess = moduleAccess.hasPermission(permission!);
      } else if (permissions != null && permissions!.isNotEmpty) {
        hasAccess = requireAll
            ? moduleAccess.hasAllPermissions(permissions!)
            : moduleAccess.hasAnyPermission(permissions!);
      }
    }

    if (!hasAccess) {
      if (hideIfNoPermission) {
        return const SizedBox.shrink();
      }
      return fallback ?? const SizedBox.shrink();
    }

    return child;
  }
}






